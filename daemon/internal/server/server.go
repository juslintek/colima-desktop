package server

import (
	"context"
	"fmt"
	"os/exec"
	"strings"

	"github.com/abiosoft/colima/app"
	"github.com/abiosoft/colima/config"
	"github.com/abiosoft/colima/config/configmanager"
	"github.com/abiosoft/colima/environment/vm/lima/limautil"
	pb "github.com/colima-desktop/daemon/proto"
	"google.golang.org/grpc"
)

type ColimaServer struct {
	pb.UnimplementedColimaServiceServer
}

func New() *ColimaServer {
	return &ColimaServer{}
}

// Register registers the ColimaService with a gRPC server (generated registrar).
func Register(s *grpc.Server) {
	pb.RegisterColimaServiceServer(s, New())
	pb.RegisterDockerServiceServer(s, NewDocker())
}

func (s *ColimaServer) newApp(profile string) (app.App, error) {
	if profile != "" && profile != "default" {
		config.SetProfile(profile)
	}
	return app.New()
}

// Start streams progress events while starting Colima.
func (s *ColimaServer) Start(req *pb.StartRequest, stream pb.ColimaService_StartServer) error {
	if req.Profile != "" {
		config.SetProfile(req.Profile)
	}

	conf := configFromProto(req.Config)

	stream.Send(&pb.ProgressEvent{Stage: "start", Message: "Starting Colima...", Progress: 0.1})

	a, err := app.New()
	if err != nil {
		return err
	}

	stream.Send(&pb.ProgressEvent{Stage: "start", Message: "Initializing VM...", Progress: 0.3})

	if err := a.Start(conf); err != nil {
		stream.Send(&pb.ProgressEvent{Stage: "start", Message: err.Error(), Progress: 1.0, Done: true, Error: err.Error()})
		return err
	}

	stream.Send(&pb.ProgressEvent{Stage: "start", Message: "Colima started", Progress: 1.0, Done: true})
	return nil
}

func (s *ColimaServer) Stop(_ context.Context, req *pb.StopRequest) (*pb.StatusResponse, error) {
	if req.Profile != "" {
		config.SetProfile(req.Profile)
	}
	a, err := app.New()
	if err != nil {
		return &pb.StatusResponse{Success: false, Error: err.Error()}, nil
	}
	if err := a.Stop(req.Force); err != nil {
		return &pb.StatusResponse{Success: false, Error: err.Error()}, nil
	}
	return &pb.StatusResponse{Success: true, Message: "Colima stopped"}, nil
}

func (s *ColimaServer) Restart(req *pb.RestartRequest, stream pb.ColimaService_RestartServer) error {
	if req.Profile != "" {
		config.SetProfile(req.Profile)
	}
	a, err := app.New()
	if err != nil {
		return err
	}
	stream.Send(&pb.ProgressEvent{Stage: "restart", Message: "Stopping...", Progress: 0.3})
	if err := a.Stop(false); err != nil {
		return err
	}
	stream.Send(&pb.ProgressEvent{Stage: "restart", Message: "Starting...", Progress: 0.6})
	conf, _ := configmanager.LoadInstance()
	if err := a.Start(conf); err != nil {
		return err
	}
	stream.Send(&pb.ProgressEvent{Stage: "restart", Message: "Restarted", Progress: 1.0, Done: true})
	return nil
}

func (s *ColimaServer) Delete(_ context.Context, req *pb.DeleteRequest) (*pb.StatusResponse, error) {
	if req.Profile != "" {
		config.SetProfile(req.Profile)
	}
	a, err := app.New()
	if err != nil {
		return &pb.StatusResponse{Success: false, Error: err.Error()}, nil
	}
	if err := a.Delete(req.Data, req.Force); err != nil {
		return &pb.StatusResponse{Success: false, Error: err.Error()}, nil
	}
	return &pb.StatusResponse{Success: true, Message: "Deleted"}, nil
}

func (s *ColimaServer) Status(_ context.Context, req *pb.StatusRequest) (*pb.VMStatus, error) {
	if req.Profile != "" {
		config.SetProfile(req.Profile)
	}
	inst, err := limautil.Instance()
	if err != nil {
		return &pb.VMStatus{Running: false}, nil
	}
	conf, _ := inst.Config()
	return &pb.VMStatus{
		Running:      inst.Running(),
		DisplayName:  inst.Name,
		Arch:         inst.Arch,
		Runtime:      inst.Runtime,
		Cpu:          int32(inst.CPU),
		Memory:       inst.Memory,
		Disk:         inst.Disk,
		IpAddress:    inst.IPAddress,
		DockerSocket: fmt.Sprintf("%s/docker.sock", config.CurrentProfile().ConfigDir()),
		MountType:    conf.MountType,
		Kubernetes:   conf.Kubernetes.Enabled,
		Version:      config.AppVersion().Version,
	}, nil
}

func (s *ColimaServer) Version(_ context.Context, _ *pb.Empty) (*pb.VersionResponse, error) {
	v := config.AppVersion()
	return &pb.VersionResponse{Version: v.Version, Revision: v.Revision}, nil
}

func (s *ColimaServer) Update(_ context.Context, _ *pb.Empty) (*pb.StatusResponse, error) {
	a, err := app.New()
	if err != nil {
		return &pb.StatusResponse{Success: false, Error: err.Error()}, nil
	}
	if err := a.Update(); err != nil {
		return &pb.StatusResponse{Success: false, Error: err.Error()}, nil
	}
	return &pb.StatusResponse{Success: true, Message: "Updated"}, nil
}

func (s *ColimaServer) Prune(_ context.Context, req *pb.PruneRequest) (*pb.StatusResponse, error) {
	args := []string{"prune", "--force"}
	if req.All {
		args = append(args, "--all")
	}
	cmd := exec.Command("colima", args...)
	if out, err := cmd.CombinedOutput(); err != nil {
		return &pb.StatusResponse{Success: false, Error: string(out)}, nil
	}
	return &pb.StatusResponse{Success: true, Message: "Pruned"}, nil
}

func (s *ColimaServer) SSHConfig(_ context.Context, req *pb.ProfileRequest) (*pb.SSHConfigResponse, error) {
	if req.Profile != "" {
		config.SetProfile(req.Profile)
	}
	cmd := exec.Command("colima", "ssh-config")
	out, err := cmd.Output()
	if err != nil {
		return nil, err
	}
	return &pb.SSHConfigResponse{Config: string(out)}, nil
}

func (s *ColimaServer) ListProfiles(_ context.Context, _ *pb.Empty) (*pb.ProfileList, error) {
	instances, err := limautil.Instances()
	if err != nil {
		return nil, err
	}
	var profiles []*pb.ProfileInfo
	for _, inst := range instances {
		profiles = append(profiles, &pb.ProfileInfo{
			Name:      inst.Name,
			Status:    inst.Status,
			Arch:      inst.Arch,
			Cpus:      int32(inst.CPU),
			Memory:    inst.Memory,
			Disk:      inst.Disk,
			Runtime:   inst.Runtime,
			IpAddress: inst.IPAddress,
		})
	}
	return &pb.ProfileList{Profiles: profiles}, nil
}

// ListMachines lists Lima VMs (mirrors `limactl list --json`).
func (s *ColimaServer) ListMachines(_ context.Context, _ *pb.Empty) (*pb.MachineList, error) {
	instances, err := limautil.Instances()
	if err != nil {
		return nil, err
	}
	var machines []*pb.MachineInfo
	for _, inst := range instances {
		machines = append(machines, &pb.MachineInfo{
			Name:   inst.Name,
			Status: inst.Status,
			Arch:   inst.Arch,
			Cpus:   int32(inst.CPU),
			Memory: inst.Memory,
			Disk:   inst.Disk,
			Os:     "linux",
		})
	}
	return &pb.MachineList{Machines: machines}, nil
}

func (s *ColimaServer) KubernetesStart(_ context.Context, req *pb.ProfileRequest) (*pb.StatusResponse, error) {
	if req.Profile != "" {
		config.SetProfile(req.Profile)
	}
	a, err := app.New()
	if err != nil {
		return &pb.StatusResponse{Success: false, Error: err.Error()}, nil
	}
	k8s, err := a.Kubernetes()
	if err != nil {
		return &pb.StatusResponse{Success: false, Error: err.Error()}, nil
	}
	if err := k8s.Start(context.Background()); err != nil {
		return &pb.StatusResponse{Success: false, Error: err.Error()}, nil
	}
	return &pb.StatusResponse{Success: true, Message: "Kubernetes started"}, nil
}

func (s *ColimaServer) KubernetesStop(_ context.Context, req *pb.ProfileRequest) (*pb.StatusResponse, error) {
	if req.Profile != "" {
		config.SetProfile(req.Profile)
	}
	a, err := app.New()
	if err != nil {
		return &pb.StatusResponse{Success: false, Error: err.Error()}, nil
	}
	k8s, err := a.Kubernetes()
	if err != nil {
		return &pb.StatusResponse{Success: false, Error: err.Error()}, nil
	}
	if err := k8s.Stop(context.Background()); err != nil {
		return &pb.StatusResponse{Success: false, Error: err.Error()}, nil
	}
	return &pb.StatusResponse{Success: true, Message: "Kubernetes stopped"}, nil
}

func (s *ColimaServer) KubernetesReset(_ context.Context, req *pb.ProfileRequest) (*pb.StatusResponse, error) {
	args := []string{"kubernetes", "reset"}
	if req.Profile != "" {
		args = append(args, "--profile", req.Profile)
	}
	cmd := exec.Command("colima", args...)
	if out, err := cmd.CombinedOutput(); err != nil {
		return &pb.StatusResponse{Success: false, Error: string(out)}, nil
	}
	return &pb.StatusResponse{Success: true, Message: "Kubernetes reset"}, nil
}

func (s *ColimaServer) KubernetesExec(_ context.Context, req *pb.KubeExecRequest) (*pb.KubeExecResponse, error) {
	args := strings.Fields(req.Command)
	cmd := exec.Command("kubectl", args...)
	out, err := cmd.CombinedOutput()
	exitCode := 0
	if err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok {
			exitCode = exitErr.ExitCode()
		}
	}
	return &pb.KubeExecResponse{Output: string(out), ExitCode: int32(exitCode)}, nil
}

func (s *ColimaServer) ProcessList(_ context.Context, req *pb.ProfileRequest) (*pb.ProcessListResponse, error) {
	if req.Profile != "" {
		config.SetProfile(req.Profile)
	}
	a, err := app.New()
	if err != nil {
		return nil, err
	}
	// Get process list via SSH
	cmd := exec.Command("colima", "ssh", "--", "ps", "aux", "--no-headers")
	out, _ := cmd.Output()
	_ = a // keep reference
	var procs []*pb.ProcessInfo
	for _, line := range strings.Split(string(out), "\n") {
		fields := strings.Fields(line)
		if len(fields) < 11 {
			continue
		}
		procs = append(procs, &pb.ProcessInfo{
			User:    fields[0],
			Pid:     parseInt32(fields[1]),
			Command: strings.Join(fields[10:], " "),
		})
	}
	return &pb.ProcessListResponse{Processes: procs}, nil
}

func (s *ColimaServer) KillProcess(_ context.Context, req *pb.KillProcessRequest) (*pb.StatusResponse, error) {
	sig := req.Signal
	if sig == 0 {
		sig = 9
	}
	cmd := exec.Command("colima", "ssh", "--", "kill", fmt.Sprintf("-%d", sig), fmt.Sprintf("%d", req.Pid))
	if out, err := cmd.CombinedOutput(); err != nil {
		return &pb.StatusResponse{Success: false, Error: string(out)}, nil
	}
	return &pb.StatusResponse{Success: true, Message: fmt.Sprintf("Process %d killed", req.Pid)}, nil
}

func (s *ColimaServer) VMStats(req *pb.ProfileRequest, stream pb.ColimaService_VMStatsServer) error {
	// In real implementation, this would poll /proc/stat and /proc/meminfo via SSH
	// and stream results. For now, single snapshot.
	cmd := exec.Command("colima", "ssh", "--", "cat", "/proc/meminfo")
	out, err := cmd.Output()
	if err != nil {
		return err
	}
	var memTotal, memAvail int64
	for _, line := range strings.Split(string(out), "\n") {
		if strings.HasPrefix(line, "MemTotal:") {
			fmt.Sscanf(line, "MemTotal: %d kB", &memTotal)
			memTotal *= 1024
		}
		if strings.HasPrefix(line, "MemAvailable:") {
			fmt.Sscanf(line, "MemAvailable: %d kB", &memAvail)
			memAvail *= 1024
		}
	}
	stream.Send(&pb.VMStatsEvent{
		MemoryTotal: memTotal,
		MemoryUsed:  memTotal - memAvail,
	})
	return nil
}

// Helpers

func parseInt32(s string) int32 {
	var v int32
	fmt.Sscanf(s, "%d", &v)
	return v
}

func configFromProto(pc *pb.ColimaConfig) config.Config {
	if pc == nil {
		return config.Config{}
	}
	return config.Config{
		CPU:                  int(pc.Cpu),
		Memory:              pc.Memory,
		Disk:                int(pc.Disk),
		RootDisk:            int(pc.RootDisk),
		Arch:                pc.Arch,
		VMType:              pc.VmType,
		CPUType:             pc.CpuType,
		VZRosetta:           pc.Rosetta,
		NestedVirtualization: pc.NestedVirtualization,
		Hostname:            pc.Hostname,
		DiskImage:           pc.DiskImage,
		PortForwarder:       pc.PortForwarder,
		Runtime:             pc.Runtime,
		ModelRunner:         pc.ModelRunner,
		MountType:           pc.MountType,
		MountINotify:        pc.MountInotify,
		ForwardAgent:        pc.ForwardAgent,
		SSHConfig:           pc.SshConfig,
		SSHPort:             int(pc.SshPort),
	}
}
