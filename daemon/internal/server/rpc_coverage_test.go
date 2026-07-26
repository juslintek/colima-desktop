package server

// Feature: cross-platform-live-verification, Property 7 (contract coverage)
//
// Per-RPC bufconn coverage + streaming race/leak checks (design Property 7;
// Requirements 3.1, 3.6). Two obligations:
//
//   1. Every one of the 65 Frozen_Contract RPCs (31 ColimaService + 34
//      DockerService) has a CONCRETE, non-`Unimplemented` server method that is
//      reachable over bufconn — i.e. calling it returns a gRPC status code other
//      than codes.Unimplemented. The embedded Unimplemented*Server returns
//      codes.Unimplemented for any method a concrete server does NOT override, so
//      "code != Unimplemented over the wire" is a sound witness that the method
//      is really implemented and wired into the generated registrar. A
//      methodology test (TestProperty7_UnimplementedDiscriminatorIsValid) proves
//      the discriminator by showing a bare Unimplemented server DOES return
//      codes.Unimplemented.
//
//   2. The streaming/cancellation paths do not leak goroutines. Run under
//      `go test -race` (see TestProperty7_StreamingCancellationDoesNotLeakGoroutines).
//
// The probe tables are cross-checked against the generated ServiceDesc method +
// stream names, so the set of probed RPCs is provably exactly the frozen
// contract (31 + 34 = 65) and the test cannot silently miss an RPC.
//
// This file never modifies production code. It reuses in-package helpers from
// server_test.go / docker_server_test.go (fakeImageClient, contextReadCloser,
// firstVMSample) and adds only distinctly-named helpers to avoid collisions with
// server_test.go, docker_server_test.go, config_server_test.go, and
// scoping_property_test.go.

import (
	"context"
	"io"
	"net"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/colima-desktop/daemon/internal/docker"
	pb "github.com/colima-desktop/daemon/proto"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/grpc/status"
	"google.golang.org/grpc/test/bufconn"
)

// coverageAbsentProfile is a profile whose ~/.colima/<p>/docker.sock cannot
// exist, so read-path docker RPCs fail fast (dial error) instead of touching the
// host's real engine, while still proving the handler is concrete.
const coverageAbsentProfile = "rpc-coverage-absent-profile"

// dialBufconn connects a client to an in-memory bufconn listener using the same
// pattern as newTestClient / newDockerClient.
func dialBufconn(t *testing.T, lis *bufconn.Listener) *grpc.ClientConn {
	t.Helper()
	conn, err := grpc.NewClient(
		"passthrough:///bufnet",
		grpc.WithContextDialer(func(ctx context.Context, _ string) (net.Conn, error) { return lis.DialContext(ctx) }),
		grpc.WithTransportCredentials(insecure.NewCredentials()),
	)
	if err != nil {
		t.Fatalf("dial bufconn: %v", err)
	}
	return conn
}

// newCoverageHarness spins up one in-memory gRPC server serving BOTH concrete
// services (exactly what production Register wires), with test doubles injected
// only at the process/socket boundaries so no real colima/docker/limactl is
// invoked and the real ~/.colima is never touched.
func newCoverageHarness(t *testing.T) (pb.ColimaServiceClient, pb.DockerServiceClient) {
	t.Helper()

	colima := New()
	// Fast, side-effect-free command doubles for the unguarded shell RPCs
	// (SSHConfig / ProcessList / VMStats). Guarded RPCs short-circuit at the
	// task-2.4 scope guards before reaching these.
	colima.commandRunner = func(context.Context, string, ...string) ([]byte, error) {
		return []byte("ok"), nil
	}
	colima.lineCommandRunner = func(_ context.Context, _ string, _ []string, onLine func(string) error) error {
		return onLine("progress")
	}
	colima.statsInterval = time.Millisecond

	dock := NewDocker()
	dock.imageClientFactory = func(docker.Target) (imageClient, error) {
		return &fakeImageClient{
			pull: func(context.Context, string) (io.ReadCloser, error) {
				return io.NopCloser(strings.NewReader(`{"status":"ok"}`)), nil
			},
			push: func(context.Context, string) (io.ReadCloser, error) {
				return io.NopCloser(strings.NewReader(`{"status":"ok"}`)), nil
			},
		}, nil
	}

	// Redirect config/template I/O to a temp dir so GetConfig/GetTemplate read
	// empties and SetTemplate writes into the sandbox, never real ~/.colima.
	base := t.TempDir()
	oldBase, oldTmpl := configBaseDir, templateFilePath
	configBaseDir = func() (string, error) { return base, nil }
	templateFilePath = func() (string, error) { return filepath.Join(base, "_templates", "default.yaml"), nil }
	t.Cleanup(func() {
		configBaseDir = oldBase
		templateFilePath = oldTmpl
	})

	lis := bufconn.Listen(1024 * 1024)
	srv := grpc.NewServer()
	pb.RegisterColimaServiceServer(srv, colima)
	pb.RegisterDockerServiceServer(srv, dock)
	go func() { _ = srv.Serve(lis) }()
	t.Cleanup(srv.Stop)

	conn := dialBufconn(t, lis)
	t.Cleanup(func() { _ = conn.Close() })
	return pb.NewColimaServiceClient(conn), pb.NewDockerServiceClient(conn)
}

// rpcCode extracts the gRPC status code that witnesses reachability. A nil error
// or a clean stream EOF is codes.OK (the handler ran and returned); any other
// error is decoded via status.Code. Only codes.Unimplemented fails Property 7.
func rpcCode(err error) codes.Code {
	if err == nil || err == io.EOF {
		return codes.OK
	}
	return status.Code(err)
}

// descRPCNames collects every MethodName + StreamName declared in a generated
// grpc.ServiceDesc — the authoritative frozen-contract RPC set for that service.
func descRPCNames(desc grpc.ServiceDesc) map[string]struct{} {
	names := make(map[string]struct{})
	for _, m := range desc.Methods {
		names[m.MethodName] = struct{}{}
	}
	for _, s := range desc.Streams {
		names[s.StreamName] = struct{}{}
	}
	return names
}

// recvOnce opens a stream and returns the error from its first Recv, cancelling
// the per-call context afterwards so no handler goroutine lingers.
func recvOnce[T any](parent context.Context, open func(context.Context) (recverT[T], error)) error {
	ctx, cancel := context.WithCancel(parent)
	defer cancel()
	stream, err := open(ctx)
	if err != nil {
		return err
	}
	_, err = stream.Recv()
	return err
}

// recverT is the minimal streaming-client shape (satisfied by every generated
// *Client stream type).
type recverT[T any] interface {
	Recv() (T, error)
}

// ─── ColimaService coverage (31 RPCs) ────────────────────────────────────────

type colimaProbe struct {
	name   string
	invoke func(context.Context, pb.ColimaServiceClient) error
}

func colimaCoverageProbes() []colimaProbe {
	return []colimaProbe{
		// Unary (26). Mutating handlers are invoked with an omitted scope so the
		// task-2.4 guard returns InvalidArgument (concrete, zero side effects,
		// never reaching app.New()/colima). Reads use benign inputs.
		{"Stop", func(ctx context.Context, c pb.ColimaServiceClient) error {
			_, err := c.Stop(ctx, &pb.StopRequest{})
			return err
		}},
		{"Delete", func(ctx context.Context, c pb.ColimaServiceClient) error {
			_, err := c.Delete(ctx, &pb.DeleteRequest{})
			return err
		}},
		{"Status", func(ctx context.Context, c pb.ColimaServiceClient) error {
			_, err := c.Status(ctx, &pb.StatusRequest{Profile: coverageAbsentProfile})
			return err
		}},
		{"Version", func(ctx context.Context, c pb.ColimaServiceClient) error {
			_, err := c.Version(ctx, &pb.Empty{})
			return err
		}},
		{"Update", func(ctx context.Context, c pb.ColimaServiceClient) error {
			_, err := c.Update(ctx, &pb.ProfileRequest{})
			return err
		}},
		{"Prune", func(ctx context.Context, c pb.ColimaServiceClient) error {
			_, err := c.Prune(ctx, &pb.PruneRequest{})
			return err
		}},
		{"SSHConfig", func(ctx context.Context, c pb.ColimaServiceClient) error {
			_, err := c.SSHConfig(ctx, &pb.ProfileRequest{Profile: coverageAbsentProfile})
			return err
		}},
		{"ListProfiles", func(ctx context.Context, c pb.ColimaServiceClient) error {
			_, err := c.ListProfiles(ctx, &pb.Empty{})
			return err
		}},
		{"ListMachines", func(ctx context.Context, c pb.ColimaServiceClient) error {
			_, err := c.ListMachines(ctx, &pb.Empty{})
			return err
		}},
		{"CreateProfile", func(ctx context.Context, c pb.ColimaServiceClient) error {
			_, err := c.CreateProfile(ctx, &pb.CreateProfileRequest{})
			return err
		}},
		{"DeleteProfile", func(ctx context.Context, c pb.ColimaServiceClient) error {
			_, err := c.DeleteProfile(ctx, &pb.DeleteProfileRequest{})
			return err
		}},
		{"CloneProfile", func(ctx context.Context, c pb.ColimaServiceClient) error {
			_, err := c.CloneProfile(ctx, &pb.CloneProfileRequest{})
			return err
		}},
		{"GetConfig", func(ctx context.Context, c pb.ColimaServiceClient) error {
			_, err := c.GetConfig(ctx, &pb.ProfileRequest{Profile: coverageAbsentProfile})
			return err
		}},
		{"SetConfig", func(ctx context.Context, c pb.ColimaServiceClient) error {
			_, err := c.SetConfig(ctx, &pb.SetConfigRequest{})
			return err
		}},
		{"GetTemplate", func(ctx context.Context, c pb.ColimaServiceClient) error {
			_, err := c.GetTemplate(ctx, &pb.Empty{})
			return err
		}},
		{"SetTemplate", func(ctx context.Context, c pb.ColimaServiceClient) error {
			_, err := c.SetTemplate(ctx, &pb.ColimaConfig{})
			return err
		}},
		{"KubernetesStart", func(ctx context.Context, c pb.ColimaServiceClient) error {
			_, err := c.KubernetesStart(ctx, &pb.ProfileRequest{})
			return err
		}},
		{"KubernetesStop", func(ctx context.Context, c pb.ColimaServiceClient) error {
			_, err := c.KubernetesStop(ctx, &pb.ProfileRequest{})
			return err
		}},
		{"KubernetesReset", func(ctx context.Context, c pb.ColimaServiceClient) error {
			_, err := c.KubernetesReset(ctx, &pb.ProfileRequest{})
			return err
		}},
		{"KubernetesExec", func(ctx context.Context, c pb.ColimaServiceClient) error {
			// Empty command short-circuits before kubectl is invoked.
			_, err := c.KubernetesExec(ctx, &pb.KubeExecRequest{})
			return err
		}},
		{"ModelServe", func(ctx context.Context, c pb.ColimaServiceClient) error {
			_, err := c.ModelServe(ctx, &pb.ModelServeRequest{})
			return err
		}},
		{"ModelStop", func(ctx context.Context, c pb.ColimaServiceClient) error {
			_, err := c.ModelStop(ctx, &pb.ProfileRequest{})
			return err
		}},
		{"SwitchRuntime", func(ctx context.Context, c pb.ColimaServiceClient) error {
			_, err := c.SwitchRuntime(ctx, &pb.SwitchRuntimeRequest{})
			return err
		}},
		{"UpdateRuntime", func(ctx context.Context, c pb.ColimaServiceClient) error {
			_, err := c.UpdateRuntime(ctx, &pb.ProfileRequest{})
			return err
		}},
		{"ProcessList", func(ctx context.Context, c pb.ColimaServiceClient) error {
			_, err := c.ProcessList(ctx, &pb.ProfileRequest{Profile: coverageAbsentProfile})
			return err
		}},
		{"KillProcess", func(ctx context.Context, c pb.ColimaServiceClient) error {
			_, err := c.KillProcess(ctx, &pb.KillProcessRequest{})
			return err
		}},
		// Server streams (5). First Recv surfaces the handler's status code.
		{"Start", func(ctx context.Context, c pb.ColimaServiceClient) error {
			return recvOnce[*pb.ProgressEvent](ctx, func(cc context.Context) (recverT[*pb.ProgressEvent], error) {
				return c.Start(cc, &pb.StartRequest{})
			})
		}},
		{"Restart", func(ctx context.Context, c pb.ColimaServiceClient) error {
			return recvOnce[*pb.ProgressEvent](ctx, func(cc context.Context) (recverT[*pb.ProgressEvent], error) {
				return c.Restart(cc, &pb.RestartRequest{})
			})
		}},
		{"ModelSetup", func(ctx context.Context, c pb.ColimaServiceClient) error {
			return recvOnce[*pb.ProgressEvent](ctx, func(cc context.Context) (recverT[*pb.ProgressEvent], error) {
				return c.ModelSetup(cc, &pb.ModelRequest{})
			})
		}},
		{"ModelRun", func(ctx context.Context, c pb.ColimaServiceClient) error {
			return recvOnce[*pb.ProgressEvent](ctx, func(cc context.Context) (recverT[*pb.ProgressEvent], error) {
				return c.ModelRun(cc, &pb.ModelRunRequest{})
			})
		}},
		{"VMStats", func(ctx context.Context, c pb.ColimaServiceClient) error {
			return recvOnce[*pb.VMStatsEvent](ctx, func(cc context.Context) (recverT[*pb.VMStatsEvent], error) {
				return c.VMStats(cc, &pb.ProfileRequest{Profile: coverageAbsentProfile})
			})
		}},
	}
}

func TestProperty7_AllColimaServiceRPCsAreConcrete(t *testing.T) {
	cc, _ := newCoverageHarness(t)
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	probes := colimaCoverageProbes()
	covered := make(map[string]struct{}, len(probes))
	for _, p := range probes {
		if _, dup := covered[p.name]; dup {
			t.Errorf("ColimaService.%s probed more than once", p.name)
		}
		covered[p.name] = struct{}{}
		if code := rpcCode(p.invoke(ctx, cc)); code == codes.Unimplemented {
			t.Errorf("ColimaService.%s returned codes.Unimplemented over bufconn — no concrete server method", p.name)
		}
	}
	assertProbesMatchContract(t, "ColimaService", covered, descRPCNames(pb.ColimaService_ServiceDesc), 31)
}

// ─── DockerService coverage (34 RPCs) ─────────────────────────────────────────

type dockerProbe struct {
	name   string
	invoke func(context.Context, pb.DockerServiceClient) error
}

func dockerCoverageProbes() []dockerProbe {
	// Mutating docker RPCs are invoked with an omitted scope: the task-2.4
	// mutatingClientFor guard sets response .Error (nil transport error → OK)
	// and makes no docker call. Read RPCs use coverageAbsentProfile so the
	// dial fails fast. Either way the code is never Unimplemented.
	scope := &pb.DockerScope{Profile: coverageAbsentProfile}
	id := func() *pb.IdRequest { return &pb.IdRequest{Id: "x", Profile: coverageAbsentProfile} }
	name := func() *pb.NameRequest { return &pb.NameRequest{Name: "x", Profile: coverageAbsentProfile} }
	return []dockerProbe{
		// Containers (10)
		{"ListContainers", func(ctx context.Context, c pb.DockerServiceClient) error {
			_, err := c.ListContainers(ctx, scope)
			return err
		}},
		{"ContainerAction", func(ctx context.Context, c pb.DockerServiceClient) error {
			_, err := c.ContainerAction(ctx, &pb.ContainerActionRequest{Id: "x", Action: "start"})
			return err
		}},
		{"CreateContainer", func(ctx context.Context, c pb.DockerServiceClient) error {
			_, err := c.CreateContainer(ctx, &pb.CreateContainerRequest{Name: "x", Image: "img"})
			return err
		}},
		{"RenameContainer", func(ctx context.Context, c pb.DockerServiceClient) error {
			_, err := c.RenameContainer(ctx, &pb.RenameRequest{Id: "x", NewName: "y"})
			return err
		}},
		{"ContainerLogs", func(ctx context.Context, c pb.DockerServiceClient) error {
			_, err := c.ContainerLogs(ctx, id())
			return err
		}},
		{"InspectContainer", func(ctx context.Context, c pb.DockerServiceClient) error {
			_, err := c.InspectContainer(ctx, id())
			return err
		}},
		{"ContainerTop", func(ctx context.Context, c pb.DockerServiceClient) error {
			_, err := c.ContainerTop(ctx, id())
			return err
		}},
		{"ContainerStats", func(ctx context.Context, c pb.DockerServiceClient) error {
			_, err := c.ContainerStats(ctx, id())
			return err
		}},
		{"ContainerChanges", func(ctx context.Context, c pb.DockerServiceClient) error {
			_, err := c.ContainerChanges(ctx, id())
			return err
		}},
		{"PruneContainers", func(ctx context.Context, c pb.DockerServiceClient) error {
			_, err := c.PruneContainers(ctx, &pb.DockerScope{})
			return err
		}},
		// Images (9)
		{"ListImages", func(ctx context.Context, c pb.DockerServiceClient) error {
			_, err := c.ListImages(ctx, scope)
			return err
		}},
		{"PullImage", func(ctx context.Context, c pb.DockerServiceClient) error {
			return recvOnce[*pb.ProgressEvent](ctx, func(cc context.Context) (recverT[*pb.ProgressEvent], error) {
				return c.PullImage(cc, &pb.NameRequest{Name: "alpine:latest", Profile: "coverage"})
			})
		}},
		{"RemoveImage", func(ctx context.Context, c pb.DockerServiceClient) error {
			_, err := c.RemoveImage(ctx, &pb.IdRequest{Id: "x"})
			return err
		}},
		{"InspectImage", func(ctx context.Context, c pb.DockerServiceClient) error {
			_, err := c.InspectImage(ctx, name())
			return err
		}},
		{"ImageHistory", func(ctx context.Context, c pb.DockerServiceClient) error {
			_, err := c.ImageHistory(ctx, name())
			return err
		}},
		{"TagImage", func(ctx context.Context, c pb.DockerServiceClient) error {
			_, err := c.TagImage(ctx, &pb.TagRequest{Name: "x", Repo: "r", Tag: "t"})
			return err
		}},
		{"PushImage", func(ctx context.Context, c pb.DockerServiceClient) error {
			return recvOnce[*pb.ProgressEvent](ctx, func(cc context.Context) (recverT[*pb.ProgressEvent], error) {
				return c.PushImage(cc, &pb.NameRequest{Name: "alpine:latest", Profile: "coverage"})
			})
		}},
		{"SearchImages", func(ctx context.Context, c pb.DockerServiceClient) error {
			_, err := c.SearchImages(ctx, &pb.SearchRequest{Term: "x", Profile: coverageAbsentProfile})
			return err
		}},
		{"PruneImages", func(ctx context.Context, c pb.DockerServiceClient) error {
			_, err := c.PruneImages(ctx, &pb.DockerScope{})
			return err
		}},
		// Volumes (5)
		{"ListVolumes", func(ctx context.Context, c pb.DockerServiceClient) error {
			_, err := c.ListVolumes(ctx, scope)
			return err
		}},
		{"CreateVolume", func(ctx context.Context, c pb.DockerServiceClient) error {
			_, err := c.CreateVolume(ctx, &pb.NameRequest{Name: "x"})
			return err
		}},
		{"RemoveVolume", func(ctx context.Context, c pb.DockerServiceClient) error {
			_, err := c.RemoveVolume(ctx, &pb.NameRequest{Name: "x"})
			return err
		}},
		{"InspectVolume", func(ctx context.Context, c pb.DockerServiceClient) error {
			_, err := c.InspectVolume(ctx, name())
			return err
		}},
		{"PruneVolumes", func(ctx context.Context, c pb.DockerServiceClient) error {
			_, err := c.PruneVolumes(ctx, &pb.DockerScope{})
			return err
		}},
		// Networks (7)
		{"ListNetworks", func(ctx context.Context, c pb.DockerServiceClient) error {
			_, err := c.ListNetworks(ctx, scope)
			return err
		}},
		{"CreateNetwork", func(ctx context.Context, c pb.DockerServiceClient) error {
			_, err := c.CreateNetwork(ctx, &pb.NameRequest{Name: "x"})
			return err
		}},
		{"RemoveNetwork", func(ctx context.Context, c pb.DockerServiceClient) error {
			_, err := c.RemoveNetwork(ctx, &pb.IdRequest{Id: "x"})
			return err
		}},
		{"InspectNetwork", func(ctx context.Context, c pb.DockerServiceClient) error {
			_, err := c.InspectNetwork(ctx, id())
			return err
		}},
		{"ConnectNetwork", func(ctx context.Context, c pb.DockerServiceClient) error {
			_, err := c.ConnectNetwork(ctx, &pb.NetworkContainerRequest{NetworkId: "n", ContainerId: "c"})
			return err
		}},
		{"DisconnectNetwork", func(ctx context.Context, c pb.DockerServiceClient) error {
			_, err := c.DisconnectNetwork(ctx, &pb.NetworkContainerRequest{NetworkId: "n", ContainerId: "c"})
			return err
		}},
		{"PruneNetworks", func(ctx context.Context, c pb.DockerServiceClient) error {
			_, err := c.PruneNetworks(ctx, &pb.DockerScope{})
			return err
		}},
		// Streams (3)
		{"StreamEvents", func(ctx context.Context, c pb.DockerServiceClient) error {
			return recvOnce[*pb.JsonResponse](ctx, func(cc context.Context) (recverT[*pb.JsonResponse], error) {
				return c.StreamEvents(cc, scope)
			})
		}},
		{"StreamLogs", func(ctx context.Context, c pb.DockerServiceClient) error {
			return recvOnce[*pb.JsonResponse](ctx, func(cc context.Context) (recverT[*pb.JsonResponse], error) {
				return c.StreamLogs(cc, id())
			})
		}},
		{"StreamStats", func(ctx context.Context, c pb.DockerServiceClient) error {
			return recvOnce[*pb.JsonResponse](ctx, func(cc context.Context) (recverT[*pb.JsonResponse], error) {
				return c.StreamStats(cc, id())
			})
		}},
	}
}

func TestProperty7_AllDockerServiceRPCsAreConcrete(t *testing.T) {
	_, dc := newCoverageHarness(t)
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	probes := dockerCoverageProbes()
	covered := make(map[string]struct{}, len(probes))
	for _, p := range probes {
		if _, dup := covered[p.name]; dup {
			t.Errorf("DockerService.%s probed more than once", p.name)
		}
		covered[p.name] = struct{}{}
		if code := rpcCode(p.invoke(ctx, dc)); code == codes.Unimplemented {
			t.Errorf("DockerService.%s returned codes.Unimplemented over bufconn — no concrete server method", p.name)
		}
	}
	assertProbesMatchContract(t, "DockerService", covered, descRPCNames(pb.DockerService_ServiceDesc), 34)
}

// TestProperty7_ContractRPCTotalIs65 ties the two per-service checks together:
// the frozen contract is exactly 31 + 34 = 65 RPCs.
func TestProperty7_ContractRPCTotalIs65(t *testing.T) {
	colimaN := len(descRPCNames(pb.ColimaService_ServiceDesc))
	dockerN := len(descRPCNames(pb.DockerService_ServiceDesc))
	if colimaN != 31 {
		t.Errorf("ColimaService declares %d RPCs, want 31", colimaN)
	}
	if dockerN != 34 {
		t.Errorf("DockerService declares %d RPCs, want 34", dockerN)
	}
	if total := colimaN + dockerN; total != 65 {
		t.Errorf("frozen contract declares %d RPCs, want 65", total)
	}
}

// assertProbesMatchContract fails if the probed RPC set differs from the
// generated ServiceDesc set, so the coverage table provably covers every RPC in
// the frozen contract and references no phantom RPC.
func assertProbesMatchContract(t *testing.T, service string, covered, contract map[string]struct{}, want int) {
	t.Helper()
	if len(contract) != want {
		t.Fatalf("%s: generated contract has %d RPCs, want %d (contract drift)", service, len(contract), want)
	}
	for rpc := range contract {
		if _, ok := covered[rpc]; !ok {
			t.Errorf("%s.%s exists in the generated contract but is not probed by this test", service, rpc)
		}
	}
	for rpc := range covered {
		if _, ok := contract[rpc]; !ok {
			t.Errorf("%s.%s is probed but is not a declared contract RPC (stale probe)", service, rpc)
		}
	}
}

// TestProperty7_UnimplementedDiscriminatorIsValid proves the witness used above
// is sound: a bare embedded Unimplemented server MUST return codes.Unimplemented
// for both unary and streaming RPCs. If this failed, "code != Unimplemented"
// would not actually witness a concrete method.
func TestProperty7_UnimplementedDiscriminatorIsValid(t *testing.T) {
	lis := bufconn.Listen(1024 * 1024)
	srv := grpc.NewServer()
	pb.RegisterColimaServiceServer(srv, pb.UnimplementedColimaServiceServer{})
	pb.RegisterDockerServiceServer(srv, pb.UnimplementedDockerServiceServer{})
	go func() { _ = srv.Serve(lis) }()
	t.Cleanup(srv.Stop)
	conn := dialBufconn(t, lis)
	t.Cleanup(func() { _ = conn.Close() })

	cc := pb.NewColimaServiceClient(conn)
	dc := pb.NewDockerServiceClient(conn)
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if _, err := cc.Version(ctx, &pb.Empty{}); status.Code(err) != codes.Unimplemented {
		t.Fatalf("bare ColimaService.Version code = %s, want Unimplemented (discriminator invalid)", status.Code(err))
	}
	if _, err := dc.ListContainers(ctx, &pb.DockerScope{}); status.Code(err) != codes.Unimplemented {
		t.Fatalf("bare DockerService.ListContainers code = %s, want Unimplemented (discriminator invalid)", status.Code(err))
	}
	// A server stream: the code surfaces on first Recv.
	streamErr := recvOnce[*pb.ProgressEvent](ctx, func(cc context.Context) (recverT[*pb.ProgressEvent], error) {
		return pb.NewColimaServiceClient(conn).Start(cc, &pb.StartRequest{})
	})
	if status.Code(streamErr) != codes.Unimplemented {
		t.Fatalf("bare ColimaService.Start code = %s, want Unimplemented (discriminator invalid)", status.Code(streamErr))
	}
}

// ─── Streaming cancellation + goroutine-leak check (Requirement 3.6) ──────────

// newLeakHarness builds a server whose streaming paths can be driven and
// cancelled deterministically with blocking fakes, and returns the two clients
// plus an idempotent stop() so the test can tear the server down before
// measuring goroutines.
func newLeakHarness(t *testing.T) (pb.ColimaServiceClient, pb.DockerServiceClient, func()) {
	t.Helper()

	colima := New()
	colima.statsInterval = time.Millisecond
	// Valid VM-stats samples so VMStats actually streams (then cancels).
	colima.commandRunner = func(context.Context, string, ...string) ([]byte, error) {
		return []byte(firstVMSample), nil
	}
	// Emit one line, then block until the stream context is cancelled — exercises
	// the streamCmd cancellation path for ModelSetup / ModelRun.
	colima.lineCommandRunner = func(ctx context.Context, _ string, _ []string, onLine func(string) error) error {
		if err := onLine("started"); err != nil {
			return err
		}
		<-ctx.Done()
		return ctx.Err()
	}

	dock := NewDocker()
	// Image bodies that block until the stream context is cancelled — exercises
	// the PullImage / PushImage cancellation + body/provider cleanup path.
	dock.imageClientFactory = func(docker.Target) (imageClient, error) {
		return &fakeImageClient{
			pull: func(ctx context.Context, _ string) (io.ReadCloser, error) {
				return &contextReadCloser{ctx: ctx, closed: make(chan struct{})}, nil
			},
			push: func(ctx context.Context, _ string) (io.ReadCloser, error) {
				return &contextReadCloser{ctx: ctx, closed: make(chan struct{})}, nil
			},
		}, nil
	}

	lis := bufconn.Listen(1024 * 1024)
	srv := grpc.NewServer()
	pb.RegisterColimaServiceServer(srv, colima)
	pb.RegisterDockerServiceServer(srv, dock)
	go func() { _ = srv.Serve(lis) }()

	conn, err := grpc.NewClient(
		"passthrough:///bufnet",
		grpc.WithContextDialer(func(ctx context.Context, _ string) (net.Conn, error) { return lis.DialContext(ctx) }),
		grpc.WithTransportCredentials(insecure.NewCredentials()),
	)
	if err != nil {
		srv.Stop()
		t.Fatalf("dial bufconn: %v", err)
	}

	var once sync.Once
	stop := func() {
		once.Do(func() {
			_ = conn.Close()
			srv.Stop()
		})
	}
	return pb.NewColimaServiceClient(conn), pb.NewDockerServiceClient(conn), stop
}

// driveCancellableStream opens a stream, receives its first event, cancels the
// context mid-stream, then drains to the terminal error — exercising the
// handler's cancellation cleanup. A stream that rejects before any event (e.g.
// a fast error path) is still a clean, non-leaking path.
func driveCancellableStream[T any](t *testing.T, name string, parent context.Context, open func(context.Context) (recverT[T], error)) {
	t.Helper()
	ctx, cancel := context.WithCancel(parent)
	defer cancel()
	stream, err := open(ctx)
	if err != nil {
		t.Fatalf("%s: open stream: %v", name, err)
	}
	if _, err := stream.Recv(); err != nil {
		return // handler already returned; nothing in flight to cancel
	}
	cancel()
	for {
		if _, err := stream.Recv(); err != nil {
			return
		}
	}
}

// TestProperty7_StreamingCancellationDoesNotLeakGoroutines drives every
// injectable streaming/cancellation path repeatedly, tears the server down, and
// asserts goroutines return to baseline. Run under `go test -race` this also
// gates the streaming/cancellation paths against data races (Requirement 3.6).
func TestProperty7_StreamingCancellationDoesNotLeakGoroutines(t *testing.T) {
	baseline := runtime.NumGoroutine()
	cc, dc, stop := newLeakHarness(t)
	t.Cleanup(stop) // safety net; the explicit stop() below runs first

	const iterations = 20
	parent := context.Background()
	for i := 0; i < iterations; i++ {
		driveCancellableStream[*pb.VMStatsEvent](t, "VMStats", parent, func(c context.Context) (recverT[*pb.VMStatsEvent], error) {
			return cc.VMStats(c, &pb.ProfileRequest{Profile: "leak"})
		})
		driveCancellableStream[*pb.ProgressEvent](t, "ModelSetup", parent, func(c context.Context) (recverT[*pb.ProgressEvent], error) {
			return cc.ModelSetup(c, &pb.ModelRequest{Profile: "leak"})
		})
		driveCancellableStream[*pb.ProgressEvent](t, "ModelRun", parent, func(c context.Context) (recverT[*pb.ProgressEvent], error) {
			return cc.ModelRun(c, &pb.ModelRunRequest{Profile: "leak", Model: "ai/test"})
		})
		driveCancellableStream[*pb.ProgressEvent](t, "PullImage", parent, func(c context.Context) (recverT[*pb.ProgressEvent], error) {
			return dc.PullImage(c, &pb.NameRequest{Name: "alpine:latest", Profile: "leak"})
		})
		driveCancellableStream[*pb.ProgressEvent](t, "PushImage", parent, func(c context.Context) (recverT[*pb.ProgressEvent], error) {
			return dc.PushImage(c, &pb.NameRequest{Name: "alpine:latest", Profile: "leak"})
		})
		driveCancellableStream[*pb.JsonResponse](t, "StreamEvents", parent, func(c context.Context) (recverT[*pb.JsonResponse], error) {
			return dc.StreamEvents(c, &pb.DockerScope{Profile: coverageAbsentProfile})
		})
		driveCancellableStream[*pb.JsonResponse](t, "StreamLogs", parent, func(c context.Context) (recverT[*pb.JsonResponse], error) {
			return dc.StreamLogs(c, &pb.IdRequest{Id: "x", Profile: coverageAbsentProfile})
		})
		driveCancellableStream[*pb.JsonResponse](t, "StreamStats", parent, func(c context.Context) (recverT[*pb.JsonResponse], error) {
			return dc.StreamStats(c, &pb.IdRequest{Id: "x", Profile: coverageAbsentProfile})
		})
	}

	stop() // close conn + stop server so streaming handler goroutines wind down
	assertGoroutinesSettle(t, baseline)
}

// assertGoroutinesSettle polls (with GC) until the goroutine count returns to
// baseline (plus a small slack for residual runtime/race goroutines) or fails
// with a full stack dump. Called after the server + client are fully closed, so
// any streaming handler that failed to observe cancellation would remain and be
// detected here.
func assertGoroutinesSettle(t *testing.T, baseline int) {
	t.Helper()
	const slack = 5
	deadline := time.Now().Add(5 * time.Second)
	var n int
	for {
		runtime.GC()
		n = runtime.NumGoroutine()
		if n <= baseline+slack {
			return
		}
		if time.Now().After(deadline) {
			break
		}
		time.Sleep(25 * time.Millisecond)
	}
	buf := make([]byte, 1<<18)
	buf = buf[:runtime.Stack(buf, true)]
	t.Fatalf("goroutine leak after streaming cancellation: have %d, baseline %d (slack %d)\n%s", n, baseline, slack, buf)
}
