package server

// config_server_test.go — bufconn integration tests for GetConfig / SetConfig /
// GetTemplate / SetTemplate.
//
// All tests use temp directories (via injectTempPaths) so the real ~/.colima is
// never touched.  Each sub-test is table-driven and validates the round-trip
// symmetry of the proto↔YAML mapping.

import (
	"context"
	"net"
	"os"
	"path/filepath"
	"testing"
	"time"

	pb "github.com/colima-desktop/daemon/proto"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/grpc/test/bufconn"
)

// ─── helpers ────────────────────────────────────────────────────────────────

// newConfigTestClient spins up a bufconn gRPC server and returns a connected
// ColimaServiceClient.  Path overrides are applied before the server starts.
func newConfigTestClient(t *testing.T, baseFn func() (string, error), tmplFn func() (string, error)) pb.ColimaServiceClient {
	t.Helper()

	old1, old2 := configBaseDir, templateFilePath
	configBaseDir = baseFn
	templateFilePath = tmplFn
	t.Cleanup(func() {
		configBaseDir = old1
		templateFilePath = old2
	})

	lis := bufconn.Listen(1 << 20)
	srv := grpc.NewServer()
	pb.RegisterColimaServiceServer(srv, New())
	go func() { _ = srv.Serve(lis) }()
	t.Cleanup(srv.Stop)

	conn, err := grpc.NewClient(
		"passthrough:///bufnet",
		grpc.WithContextDialer(func(ctx context.Context, _ string) (net.Conn, error) {
			return lis.DialContext(ctx)
		}),
		grpc.WithTransportCredentials(insecure.NewCredentials()),
	)
	if err != nil {
		t.Fatalf("dial bufconn: %v", err)
	}
	t.Cleanup(func() { _ = conn.Close() })
	return pb.NewColimaServiceClient(conn)
}

// injectTempPaths creates a temp base dir and returns path override functions
// for both the config base and the template file.
func injectTempPaths(t *testing.T) (baseDir string, baseFn, tmplFn func() (string, error)) {
	t.Helper()
	baseDir = t.TempDir()
	baseFn = func() (string, error) { return baseDir, nil }
	tmplFn = func() (string, error) {
		return filepath.Join(baseDir, "_templates", "default.yaml"), nil
	}
	return
}

func ctxTimeout(t *testing.T) (context.Context, context.CancelFunc) {
	return context.WithTimeout(context.Background(), 5*time.Second)
}

// ─── GetConfig ───────────────────────────────────────────────────────────────

func TestGetConfig_FileNotExist_ReturnsEmpty(t *testing.T) {
	baseDir, baseFn, tmplFn := injectTempPaths(t)
	_ = baseDir
	client := newConfigTestClient(t, baseFn, tmplFn)

	ctx, cancel := ctxTimeout(t)
	defer cancel()

	resp, err := client.GetConfig(ctx, &pb.ProfileRequest{Profile: "noexist"})
	if err != nil {
		t.Fatalf("GetConfig error: %v", err)
	}
	if resp == nil {
		t.Fatal("nil ColimaConfig")
	}
	// file absent → zero-value config
	if resp.Cpu != 0 || resp.Runtime != "" {
		t.Errorf("expected empty config, got cpu=%d runtime=%q", resp.Cpu, resp.Runtime)
	}
}

func TestGetConfig_ReadsExistingYAML(t *testing.T) {
	baseDir, baseFn, tmplFn := injectTempPaths(t)
	client := newConfigTestClient(t, baseFn, tmplFn)

	// write a colima.yaml for profile "myprofile"
	profileDir := filepath.Join(baseDir, "myprofile")
	if err := os.MkdirAll(profileDir, 0755); err != nil {
		t.Fatal(err)
	}
	yaml := `cpu: 4
memory: 8
disk: 60
arch: aarch64
runtime: docker
hostname: testhost
kubernetes:
  enabled: true
  version: v1.28.0
  k3sArgs:
    - --disable=traefik
  port: 0
`
	if err := os.WriteFile(filepath.Join(profileDir, "colima.yaml"), []byte(yaml), 0644); err != nil {
		t.Fatal(err)
	}

	ctx, cancel := ctxTimeout(t)
	defer cancel()

	resp, err := client.GetConfig(ctx, &pb.ProfileRequest{Profile: "myprofile"})
	if err != nil {
		t.Fatalf("GetConfig error: %v", err)
	}
	if resp.Cpu != 4 {
		t.Errorf("cpu: want 4 got %d", resp.Cpu)
	}
	if resp.Memory != 8 {
		t.Errorf("memory: want 8 got %f", resp.Memory)
	}
	if resp.Disk != 60 {
		t.Errorf("disk: want 60 got %d", resp.Disk)
	}
	if resp.Hostname != "testhost" {
		t.Errorf("hostname: want testhost got %q", resp.Hostname)
	}
	if resp.Kubernetes == nil || !resp.Kubernetes.Enabled {
		t.Error("kubernetes.enabled should be true")
	}
}

func TestGetConfig_DefaultProfile(t *testing.T) {
	baseDir, baseFn, tmplFn := injectTempPaths(t)
	client := newConfigTestClient(t, baseFn, tmplFn)

	defaultDir := filepath.Join(baseDir, "default")
	if err := os.MkdirAll(defaultDir, 0755); err != nil {
		t.Fatal(err)
	}
	yaml := `cpu: 2
memory: 4
disk: 100
runtime: containerd
`
	if err := os.WriteFile(filepath.Join(defaultDir, "colima.yaml"), []byte(yaml), 0644); err != nil {
		t.Fatal(err)
	}

	tests := []struct{ profile string }{{"default"}, {""}, {"colima"}}
	for _, tt := range tests {
		t.Run("profile="+tt.profile, func(t *testing.T) {
			ctx, cancel := ctxTimeout(t)
			defer cancel()
			resp, err := client.GetConfig(ctx, &pb.ProfileRequest{Profile: tt.profile})
			if err != nil {
				t.Fatalf("GetConfig error: %v", err)
			}
			if resp.Runtime != "containerd" {
				t.Errorf("runtime: want containerd got %q", resp.Runtime)
			}
		})
	}
}

// ─── SetConfig ───────────────────────────────────────────────────────────────

func TestSetConfig_WritesYAML(t *testing.T) {
	baseDir, baseFn, tmplFn := injectTempPaths(t)
	client := newConfigTestClient(t, baseFn, tmplFn)

	ctx, cancel := ctxTimeout(t)
	defer cancel()

	cfg := &pb.ColimaConfig{
		Cpu:     4,
		Memory:  8,
		Disk:    50,
		Runtime: "docker",
		Arch:    "aarch64",
		VmType:  "vz",
	}
	resp, err := client.SetConfig(ctx, &pb.SetConfigRequest{Profile: "newprofile", Config: cfg})
	if err != nil {
		t.Fatalf("SetConfig error: %v", err)
	}
	if !resp.Success {
		t.Fatalf("SetConfig not successful: %s", resp.Error)
	}

	// verify file was created
	written := filepath.Join(baseDir, "newprofile", "colima.yaml")
	data, err := os.ReadFile(written)
	if err != nil {
		t.Fatalf("cannot read written file: %v", err)
	}
	content := string(data)
	for _, want := range []string{"cpu:", "memory:", "disk:", "runtime:", "arch:", "vmType:"} {
		found := false
		for _, line := range splitLines(content) {
			if len(line) >= len(want) && line[:len(want)] == want {
				found = true
				break
			}
		}
		if !found {
			t.Errorf("written YAML missing key %q\ncontent:\n%s", want, content)
		}
	}
}

func TestSetConfig_NilConfig_ReturnsError(t *testing.T) {
	_, baseFn, tmplFn := injectTempPaths(t)
	client := newConfigTestClient(t, baseFn, tmplFn)

	ctx, cancel := ctxTimeout(t)
	defer cancel()

	resp, err := client.SetConfig(ctx, &pb.SetConfigRequest{Profile: "x", Config: nil})
	if err != nil {
		t.Fatalf("unexpected gRPC error: %v", err)
	}
	if resp.Success {
		t.Error("expected failure for nil config")
	}
}

// ─── GetTemplate ─────────────────────────────────────────────────────────────

func TestGetTemplate_NoFile_ReturnsEmpty(t *testing.T) {
	_, baseFn, tmplFn := injectTempPaths(t)
	client := newConfigTestClient(t, baseFn, tmplFn)

	ctx, cancel := ctxTimeout(t)
	defer cancel()

	resp, err := client.GetTemplate(ctx, &pb.Empty{})
	if err != nil {
		t.Fatalf("GetTemplate error: %v", err)
	}
	if resp == nil {
		t.Fatal("nil ColimaConfig")
	}
}

func TestGetTemplate_ReadsTemplateFile(t *testing.T) {
	baseDir, baseFn, tmplFn := injectTempPaths(t)
	client := newConfigTestClient(t, baseFn, tmplFn)

	// write template file
	templDir := filepath.Join(baseDir, "_templates")
	if err := os.MkdirAll(templDir, 0755); err != nil {
		t.Fatal(err)
	}
	yaml := `cpu: 6
memory: 12
disk: 200
runtime: containerd
arch: aarch64
`
	if err := os.WriteFile(filepath.Join(templDir, "default.yaml"), []byte(yaml), 0644); err != nil {
		t.Fatal(err)
	}

	ctx, cancel := ctxTimeout(t)
	defer cancel()

	resp, err := client.GetTemplate(ctx, &pb.Empty{})
	if err != nil {
		t.Fatalf("GetTemplate error: %v", err)
	}
	if resp.Cpu != 6 {
		t.Errorf("cpu: want 6 got %d", resp.Cpu)
	}
	if resp.Memory != 12 {
		t.Errorf("memory: want 12 got %f", resp.Memory)
	}
	if resp.Runtime != "containerd" {
		t.Errorf("runtime: want containerd got %q", resp.Runtime)
	}
}

// ─── SetTemplate ─────────────────────────────────────────────────────────────

func TestSetTemplate_WritesTemplateFile(t *testing.T) {
	baseDir, baseFn, tmplFn := injectTempPaths(t)
	client := newConfigTestClient(t, baseFn, tmplFn)

	ctx, cancel := ctxTimeout(t)
	defer cancel()

	cfg := &pb.ColimaConfig{
		Cpu:     8,
		Memory:  16,
		Disk:    100,
		Runtime: "docker",
		Arch:    "aarch64",
		VmType:  "vz",
	}
	resp, err := client.SetTemplate(ctx, cfg)
	if err != nil {
		t.Fatalf("SetTemplate error: %v", err)
	}
	if !resp.Success {
		t.Fatalf("SetTemplate not successful: %s", resp.Error)
	}

	written := filepath.Join(baseDir, "_templates", "default.yaml")
	if _, err := os.Stat(written); err != nil {
		t.Fatalf("template file not created: %v", err)
	}
	data, err := os.ReadFile(written)
	if err != nil {
		t.Fatalf("cannot read template file: %v", err)
	}
	content := string(data)
	if len(content) == 0 {
		t.Error("template file is empty")
	}
}

// ─── Round-trip symmetry ─────────────────────────────────────────────────────

// TestSetConfig_GetConfig_RoundTrip verifies that what is written via SetConfig
// can be read back identically via GetConfig.
func TestSetConfig_GetConfig_RoundTrip(t *testing.T) {
	baseDir, baseFn, tmplFn := injectTempPaths(t)
	_ = baseDir
	client := newConfigTestClient(t, baseFn, tmplFn)

	cases := []struct {
		name string
		cfg  *pb.ColimaConfig
	}{
		{
			name: "basic",
			cfg: &pb.ColimaConfig{
				Cpu:     4,
				Memory:  8,
				Disk:    60,
				Runtime: "docker",
				Arch:    "aarch64",
				VmType:  "vz",
			},
		},
		{
			name: "with_kubernetes",
			cfg: &pb.ColimaConfig{
				Cpu:     2,
				Memory:  4,
				Disk:    50,
				Runtime: "docker",
				Arch:    "aarch64",
				Kubernetes: &pb.KubernetesConfig{
					Enabled: true,
					Version: "v1.28.0",
					K3SArgs: []string{"--disable=traefik"},
					Port:    0,
				},
			},
		},
		{
			name: "with_network",
			cfg: &pb.ColimaConfig{
				Cpu:     2,
				Memory:  2,
				Disk:    40,
				Runtime: "docker",
				Arch:    "aarch64",
				Network: &pb.NetworkConfig{
					Address:        true,
					Mode:           "shared",
					Dns:            []string{"8.8.8.8", "1.1.1.1"},
					GatewayAddress: "192.168.5.2",
				},
			},
		},
		{
			name: "with_mounts_and_provision",
			cfg: &pb.ColimaConfig{
				Cpu:     2,
				Memory:  2,
				Disk:    40,
				Runtime: "docker",
				Arch:    "aarch64",
				Mounts: []*pb.Mount{
					{Location: "/Users/test", Writable: true},
					{Location: "/data", MountPoint: "/mnt/data", Writable: false},
				},
				Provision: []*pb.Provision{
					{Mode: "system", Script: "#!/bin/bash\necho hi"},
				},
				Env: map[string]string{"MY_VAR": "hello"},
			},
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			profile := "roundtrip-" + tc.name
			ctx, cancel := ctxTimeout(t)
			defer cancel()

			setResp, err := client.SetConfig(ctx, &pb.SetConfigRequest{Profile: profile, Config: tc.cfg})
			if err != nil {
				t.Fatalf("SetConfig: %v", err)
			}
			if !setResp.Success {
				t.Fatalf("SetConfig failed: %s", setResp.Error)
			}

			ctx2, cancel2 := ctxTimeout(t)
			defer cancel2()
			got, err := client.GetConfig(ctx2, &pb.ProfileRequest{Profile: profile})
			if err != nil {
				t.Fatalf("GetConfig: %v", err)
			}

			if got.Cpu != tc.cfg.Cpu {
				t.Errorf("cpu: want %d got %d", tc.cfg.Cpu, got.Cpu)
			}
			if got.Memory != tc.cfg.Memory {
				t.Errorf("memory: want %f got %f", tc.cfg.Memory, got.Memory)
			}
			if got.Disk != tc.cfg.Disk {
				t.Errorf("disk: want %d got %d", tc.cfg.Disk, got.Disk)
			}
			if got.Runtime != tc.cfg.Runtime {
				t.Errorf("runtime: want %q got %q", tc.cfg.Runtime, got.Runtime)
			}
			if got.Arch != tc.cfg.Arch {
				t.Errorf("arch: want %q got %q", tc.cfg.Arch, got.Arch)
			}

			if tc.cfg.Kubernetes != nil && got.Kubernetes != nil {
				if got.Kubernetes.Enabled != tc.cfg.Kubernetes.Enabled {
					t.Errorf("k8s.enabled: want %v got %v", tc.cfg.Kubernetes.Enabled, got.Kubernetes.Enabled)
				}
				if got.Kubernetes.Version != tc.cfg.Kubernetes.Version {
					t.Errorf("k8s.version: want %q got %q", tc.cfg.Kubernetes.Version, got.Kubernetes.Version)
				}
			}

			if tc.cfg.Network != nil && got.Network != nil {
				if got.Network.Address != tc.cfg.Network.Address {
					t.Errorf("network.address: want %v got %v", tc.cfg.Network.Address, got.Network.Address)
				}
			}

			if want, got2 := len(tc.cfg.Mounts), len(got.Mounts); got2 != want {
				t.Errorf("mounts count: want %d got %d", want, got2)
			}
			if want, got2 := len(tc.cfg.Provision), len(got.Provision); got2 != want {
				t.Errorf("provision count: want %d got %d", want, got2)
			}
			if want, got2 := len(tc.cfg.Env), len(got.Env); got2 != want {
				t.Errorf("env count: want %d got %d", want, got2)
			}
		})
	}
}

// TestSetTemplate_GetTemplate_RoundTrip verifies template write+read symmetry.
func TestSetTemplate_GetTemplate_RoundTrip(t *testing.T) {
	_, baseFn, tmplFn := injectTempPaths(t)
	client := newConfigTestClient(t, baseFn, tmplFn)

	want := &pb.ColimaConfig{
		Cpu:         4,
		Memory:      8,
		Disk:        100,
		Runtime:     "docker",
		Arch:        "aarch64",
		VmType:      "vz",
		MountType:   "virtiofs",
		PortForwarder: "ssh",
	}

	ctx, cancel := ctxTimeout(t)
	defer cancel()
	if setResp, err := client.SetTemplate(ctx, want); err != nil || !setResp.Success {
		t.Fatalf("SetTemplate: err=%v resp=%v", err, setResp)
	}

	ctx2, cancel2 := ctxTimeout(t)
	defer cancel2()
	got, err := client.GetTemplate(ctx2, &pb.Empty{})
	if err != nil {
		t.Fatalf("GetTemplate: %v", err)
	}
	if got.Cpu != want.Cpu {
		t.Errorf("cpu: want %d got %d", want.Cpu, got.Cpu)
	}
	if got.Runtime != want.Runtime {
		t.Errorf("runtime: want %q got %q", want.Runtime, got.Runtime)
	}
	if got.VmType != want.VmType {
		t.Errorf("vmType: want %q got %q", want.VmType, got.VmType)
	}
}

// ─── internal utility ────────────────────────────────────────────────────────

func splitLines(s string) []string {
	var out []string
	start := 0
	for i := 0; i < len(s); i++ {
		if s[i] == '\n' {
			out = append(out, s[start:i])
			start = i + 1
		}
	}
	if start < len(s) {
		out = append(out, s[start:])
	}
	return out
}
