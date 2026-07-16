package server

// config_server.go — GetConfig / SetConfig / GetTemplate / SetTemplate handlers.
//
// Reads and writes colima YAML files directly (no interactive CLI commands):
//   - Profile config:  ~/.colima/<profile>/colima.yaml
//   - Template:        ~/.colima/_templates/default.yaml
//
// Path helpers (configBaseDir, templateFilePath) are package-level variables so
// integration tests can inject temp directories without touching real ~/.colima.

import (
	"context"
	"fmt"
	"net"
	"os"
	"path/filepath"

	"github.com/abiosoft/colima/config"
	pb "github.com/colima-desktop/daemon/proto"
	"gopkg.in/yaml.v3"
)

// ─── Injectable path helpers ────────────────────────────────────────────────

// configBaseDir returns the colima base directory (defaults to ~/.colima).
// Override in tests via setConfigBaseDir.
var configBaseDir = defaultConfigBaseDir

// templateFilePath returns the path to the default template file.
// Override in tests via setTemplateFilePath.
var templateFilePath = defaultTemplatePath

func defaultConfigBaseDir() (string, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return "", fmt.Errorf("cannot resolve home dir: %w", err)
	}
	return filepath.Join(home, ".colima"), nil
}

func defaultTemplatePath() (string, error) {
	base, err := defaultConfigBaseDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(base, "_templates", "default.yaml"), nil
}

// profileConfigPath resolves ~/.colima/<shortName>/colima.yaml.
// "default" and "" both map to ~/.colima/default/colima.yaml.
func profileConfigPath(profile string) (string, error) {
	base, err := configBaseDir()
	if err != nil {
		return "", err
	}
	shortName := profileShortName(profile)
	return filepath.Join(base, shortName, "colima.yaml"), nil
}

// profileShortName converts a profile name to its directory component, mirroring
// colima's ProfileFromName logic:
//   - "" | "colima" | "default" → "default"
//   - anything else             → the name as-is (colima strips "colima-" prefix internally
//     and stores under the short name)
func profileShortName(name string) string {
	switch name {
	case "", "colima", "default":
		return "default"
	}
	// colima stores profiles under the short name (without "colima-" prefix)
	return name
}

// ─── RPC handlers ───────────────────────────────────────────────────────────

// GetConfig reads the YAML config for the requested profile and returns it as a
// proto ColimaConfig.  If the file does not exist, an empty ColimaConfig is returned.
func (s *ColimaServer) GetConfig(_ context.Context, req *pb.ProfileRequest) (*pb.ColimaConfig, error) {
	path, err := profileConfigPath(req.GetProfile())
	if err != nil {
		return nil, err
	}
	return loadConfigProto(path)
}

// SetConfig writes a proto ColimaConfig to the profile's colima.yaml file.
// The directory is created if it does not exist.
func (s *ColimaServer) SetConfig(_ context.Context, req *pb.SetConfigRequest) (*pb.StatusResponse, error) {
	if req.GetConfig() == nil {
		return &pb.StatusResponse{Success: false, Error: "config is required"}, nil
	}
	path, err := profileConfigPath(req.GetProfile())
	if err != nil {
		return nil, err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		return &pb.StatusResponse{Success: false, Error: fmt.Sprintf("cannot create config dir: %v", err)}, nil
	}
	cfg := protoToConfig(req.GetConfig())
	if err := saveConfigYAML(cfg, path); err != nil {
		return &pb.StatusResponse{Success: false, Error: err.Error()}, nil
	}
	return &pb.StatusResponse{Success: true, Message: "config saved"}, nil
}

// GetTemplate reads the default template file and returns it as a proto ColimaConfig.
// If the template does not exist, an empty ColimaConfig is returned.
func (s *ColimaServer) GetTemplate(_ context.Context, _ *pb.Empty) (*pb.ColimaConfig, error) {
	path, err := templateFilePath()
	if err != nil {
		return nil, err
	}
	return loadConfigProto(path)
}

// SetTemplate writes a proto ColimaConfig as the default template YAML.
// The templates directory is created if it does not exist.
func (s *ColimaServer) SetTemplate(_ context.Context, pc *pb.ColimaConfig) (*pb.StatusResponse, error) {
	path, err := templateFilePath()
	if err != nil {
		return nil, err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		return &pb.StatusResponse{Success: false, Error: fmt.Sprintf("cannot create templates dir: %v", err)}, nil
	}
	cfg := protoToConfig(pc)
	if err := saveConfigYAML(cfg, path); err != nil {
		return &pb.StatusResponse{Success: false, Error: err.Error()}, nil
	}
	return &pb.StatusResponse{Success: true, Message: "template saved"}, nil
}

// ─── YAML I/O helpers ───────────────────────────────────────────────────────

// loadConfigProto reads a colima YAML file and converts it to pb.ColimaConfig.
// Returns an empty ColimaConfig (no error) when the file is absent.
func loadConfigProto(path string) (*pb.ColimaConfig, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return &pb.ColimaConfig{}, nil
		}
		return nil, fmt.Errorf("cannot read %s: %w", path, err)
	}
	var cfg config.Config
	if err := yaml.Unmarshal(data, &cfg); err != nil {
		return nil, fmt.Errorf("cannot parse %s: %w", path, err)
	}
	return configToProto(cfg), nil
}

// saveConfigYAML marshals a config.Config to YAML and writes it atomically.
func saveConfigYAML(cfg config.Config, path string) error {
	data, err := yaml.Marshal(cfg)
	if err != nil {
		return fmt.Errorf("cannot marshal config: %w", err)
	}
	if err := os.WriteFile(path, data, 0644); err != nil {
		return fmt.Errorf("cannot write %s: %w", path, err)
	}
	return nil
}

// ─── Bidirectional mappers ───────────────────────────────────────────────────

// configToProto converts a colima config.Config to a pb.ColimaConfig.
func configToProto(c config.Config) *pb.ColimaConfig {
	pc := &pb.ColimaConfig{
		Cpu:                  int32(c.CPU),
		Memory:               c.Memory,
		Disk:                 int32(c.Disk),
		RootDisk:             int32(c.RootDisk),
		Arch:                 c.Arch,
		VmType:               c.VMType,
		CpuType:              c.CPUType,
		Rosetta:              c.VZRosetta,
		NestedVirtualization: c.NestedVirtualization,
		Hostname:             c.Hostname,
		DiskImage:            c.DiskImage,
		PortForwarder:        c.PortForwarder,
		Runtime:              c.Runtime,
		ModelRunner:          c.ModelRunner,
		MountType:            c.MountType,
		MountInotify:         c.MountINotify,
		ForwardAgent:         c.ForwardAgent,
		SshConfig:            c.SSHConfig,
		SshPort:              int32(c.SSHPort),
	}

	// binfmt (*bool)
	if c.Binfmt != nil {
		pc.Binfmt = *c.Binfmt
	}

	// autoActivate (*bool)
	if c.ActivateRuntime != nil {
		pc.AutoActivate = *c.ActivateRuntime
	} else {
		pc.AutoActivate = true // colima default
	}

	// network
	pc.Network = networkToProto(c.Network)

	// kubernetes
	pc.Kubernetes = &pb.KubernetesConfig{
		Enabled: c.Kubernetes.Enabled,
		Version: c.Kubernetes.Version,
		K3SArgs: c.Kubernetes.K3sArgs,
		Port:    int32(c.Kubernetes.Port),
	}

	// docker map[string]any → map[string]string (stringify values)
	if len(c.Docker) > 0 {
		pc.Docker = make(map[string]string, len(c.Docker))
		for k, v := range c.Docker {
			pc.Docker[k] = fmt.Sprintf("%v", v)
		}
	}

	// mounts
	for _, m := range c.Mounts {
		pc.Mounts = append(pc.Mounts, &pb.Mount{
			Location:   m.Location,
			MountPoint: m.MountPoint,
			Writable:   m.Writable,
		})
	}

	// provision
	for _, p := range c.Provision {
		pc.Provision = append(pc.Provision, &pb.Provision{
			Mode:   p.Mode,
			Script: p.Script,
		})
	}

	// env
	if len(c.Env) > 0 {
		pc.Env = make(map[string]string, len(c.Env))
		for k, v := range c.Env {
			pc.Env[k] = v
		}
	}

	return pc
}

// networkToProto converts a config.Network to a pb.NetworkConfig.
func networkToProto(n config.Network) *pb.NetworkConfig {
	nc := &pb.NetworkConfig{
		Address:        n.Address,
		Mode:           n.Mode,
		Interface:      n.BridgeInterface,
		HostAddresses:  n.HostAddresses,
		PreferredRoute: n.PreferredRoute,
	}
	for _, ip := range n.DNSResolvers {
		if ip != nil {
			nc.Dns = append(nc.Dns, ip.String())
		}
	}
	if n.DNSHosts != nil {
		nc.DnsHosts = n.DNSHosts
	}
	if n.GatewayAddress != nil {
		nc.GatewayAddress = n.GatewayAddress.String()
	}
	return nc
}

// protoToConfig converts a pb.ColimaConfig to a colima config.Config.
func protoToConfig(pc *pb.ColimaConfig) config.Config {
	if pc == nil {
		return config.Config{}
	}

	binfmt := pc.Binfmt
	autoActivate := pc.AutoActivate

	c := config.Config{
		CPU:                  int(pc.Cpu),
		Memory:               pc.Memory,
		Disk:                 int(pc.Disk),
		RootDisk:             int(pc.RootDisk),
		Arch:                 pc.Arch,
		VMType:               pc.VmType,
		CPUType:              pc.CpuType,
		VZRosetta:            pc.Rosetta,
		NestedVirtualization: pc.NestedVirtualization,
		Hostname:             pc.Hostname,
		DiskImage:            pc.DiskImage,
		PortForwarder:        pc.PortForwarder,
		Runtime:              pc.Runtime,
		ModelRunner:          pc.ModelRunner,
		MountType:            pc.MountType,
		MountINotify:         pc.MountInotify,
		ForwardAgent:         pc.ForwardAgent,
		SSHConfig:            pc.SshConfig,
		SSHPort:              int(pc.SshPort),
		Binfmt:               &binfmt,
		ActivateRuntime:      &autoActivate,
	}

	// network
	if n := pc.Network; n != nil {
		c.Network = protoToNetwork(n)
	}

	// kubernetes
	if k := pc.Kubernetes; k != nil {
		c.Kubernetes = config.Kubernetes{
			Enabled: k.Enabled,
			Version: k.Version,
			K3sArgs: k.K3SArgs,
			Port:    int(k.Port),
		}
	}

	// docker map[string]string → map[string]any
	if len(pc.Docker) > 0 {
		c.Docker = make(map[string]any, len(pc.Docker))
		for k, v := range pc.Docker {
			c.Docker[k] = v
		}
	}

	// mounts
	for _, m := range pc.Mounts {
		c.Mounts = append(c.Mounts, config.Mount{
			Location:   m.Location,
			MountPoint: m.MountPoint,
			Writable:   m.Writable,
		})
	}

	// provision
	for _, p := range pc.Provision {
		c.Provision = append(c.Provision, config.Provision{
			Mode:   p.Mode,
			Script: p.Script,
		})
	}

	// env
	if len(pc.Env) > 0 {
		c.Env = make(map[string]string, len(pc.Env))
		for k, v := range pc.Env {
			c.Env[k] = v
		}
	}

	return c
}

// protoToNetwork converts a pb.NetworkConfig to a config.Network.
func protoToNetwork(n *pb.NetworkConfig) config.Network {
	if n == nil {
		return config.Network{}
	}
	cn := config.Network{
		Address:         n.Address,
		Mode:            n.Mode,
		BridgeInterface: n.Interface,
		HostAddresses:   n.HostAddresses,
		PreferredRoute:  n.PreferredRoute,
	}
	for _, s := range n.Dns {
		if ip := net.ParseIP(s); ip != nil {
			cn.DNSResolvers = append(cn.DNSResolvers, ip)
		}
	}
	if n.DnsHosts != nil {
		cn.DNSHosts = n.DnsHosts
	}
	if n.GatewayAddress != "" {
		cn.GatewayAddress = net.ParseIP(n.GatewayAddress)
	}
	return cn
}
