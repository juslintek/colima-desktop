package server

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/abiosoft/colima/app"
	"github.com/abiosoft/colima/config"
	"github.com/abiosoft/colima/config/configmanager"
	"github.com/abiosoft/colima/environment/vm/lima/limautil"
	pb "github.com/colima-desktop/daemon/proto"
	"github.com/google/shlex"
	"google.golang.org/grpc"
)

type ColimaServer struct {
	pb.UnimplementedColimaServiceServer
	commandRunner     commandRunner
	lineCommandRunner lineCommandRunner
	statsInterval     time.Duration
}

var colimaProfileMu sync.Mutex

func New() *ColimaServer {
	return &ColimaServer{
		commandRunner:     defaultCommandRunner,
		lineCommandRunner: defaultLineCommandRunner,
		statsInterval:     time.Second,
	}
}

// Register registers the ColimaService with a gRPC server (generated registrar).
func Register(s *grpc.Server) {
	pb.RegisterColimaServiceServer(s, New())
	pb.RegisterDockerServiceServer(s, NewDocker())
}

// Start streams progress events while starting Colima.
func (s *ColimaServer) Start(req *pb.StartRequest, stream pb.ColimaService_StartServer) error {
	if err := requireProfile(req.Profile); err != nil {
		return err
	}
	colimaProfileMu.Lock()
	defer colimaProfileMu.Unlock()
	config.SetProfile(normalizedProfile(req.Profile))

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
	if err := requireProfile(req.Profile); err != nil {
		return nil, err
	}
	colimaProfileMu.Lock()
	defer colimaProfileMu.Unlock()
	config.SetProfile(normalizedProfile(req.Profile))
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
	if err := requireProfile(req.Profile); err != nil {
		return err
	}
	colimaProfileMu.Lock()
	defer colimaProfileMu.Unlock()
	config.SetProfile(normalizedProfile(req.Profile))
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
	if err := requireProfile(req.Profile); err != nil {
		return nil, err
	}
	colimaProfileMu.Lock()
	defer colimaProfileMu.Unlock()
	config.SetProfile(normalizedProfile(req.Profile))
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
	colimaProfileMu.Lock()
	defer colimaProfileMu.Unlock()
	config.SetProfile(normalizedProfile(req.Profile))
	inst, err := limautil.Instance()
	if err != nil {
		return &pb.VMStatus{Running: false}, nil
	}
	conf, _ := inst.Config()
	runtime := effectiveRuntime(inst.Runtime, conf.Runtime)
	return &pb.VMStatus{
		Running:      inst.Running(),
		DisplayName:  inst.Name,
		Arch:         inst.Arch,
		Runtime:      runtime,
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

func effectiveRuntime(instanceRuntime, configRuntime string) string {
	if runtime := strings.TrimSpace(instanceRuntime); runtime != "" {
		return runtime
	}
	// limautil.Instance() is backed by `limactl list <id> --json`, whose
	// payload does not include Colima's runtime. Instances() fills this in,
	// but the single-instance path does not. The persisted profile config is
	// authoritative here and prevents Status from reporting an empty runtime.
	return strings.TrimSpace(configRuntime)
}

func (s *ColimaServer) Version(_ context.Context, _ *pb.Empty) (*pb.VersionResponse, error) {
	v := config.AppVersion()
	return &pb.VersionResponse{Version: v.Version, Revision: v.Revision}, nil
}

func (s *ColimaServer) Update(ctx context.Context, req *pb.ProfileRequest) (*pb.StatusResponse, error) {
	if err := requireProfile(req.Profile); err != nil {
		return nil, err
	}
	return s.run(ctx, colimaProfileArgs(req.Profile, "update")...)
}

func (s *ColimaServer) Prune(ctx context.Context, req *pb.PruneRequest) (*pb.StatusResponse, error) {
	if err := requireProfile(req.Profile); err != nil {
		return nil, err
	}
	args := colimaProfileArgs(req.Profile, "prune", "--force")
	if req.All {
		args = append(args, "--all")
	}
	return s.run(ctx, args...)
}

func (s *ColimaServer) SSHConfig(ctx context.Context, req *pb.ProfileRequest) (*pb.SSHConfigResponse, error) {
	args := colimaProfileArgs(req.Profile, "ssh-config")
	out, err := s.execute(ctx, "colima", args...)
	if err != nil {
		return nil, commandFailure("colima", args, out, err)
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

func (s *ColimaServer) KubernetesStart(ctx context.Context, req *pb.ProfileRequest) (*pb.StatusResponse, error) {
	if err := requireProfile(req.Profile); err != nil {
		return nil, err
	}
	colimaProfileMu.Lock()
	defer colimaProfileMu.Unlock()
	config.SetProfile(normalizedProfile(req.Profile))
	a, err := app.New()
	if err != nil {
		return &pb.StatusResponse{Success: false, Error: err.Error()}, nil
	}
	k8s, err := a.Kubernetes()
	if err != nil {
		return &pb.StatusResponse{Success: false, Error: err.Error()}, nil
	}
	if err := k8s.Start(ctx); err != nil {
		return &pb.StatusResponse{Success: false, Error: err.Error()}, nil
	}
	return &pb.StatusResponse{Success: true, Message: "Kubernetes started"}, nil
}

func (s *ColimaServer) KubernetesStop(ctx context.Context, req *pb.ProfileRequest) (*pb.StatusResponse, error) {
	if err := requireProfile(req.Profile); err != nil {
		return nil, err
	}
	colimaProfileMu.Lock()
	defer colimaProfileMu.Unlock()
	config.SetProfile(normalizedProfile(req.Profile))
	a, err := app.New()
	if err != nil {
		return &pb.StatusResponse{Success: false, Error: err.Error()}, nil
	}
	k8s, err := a.Kubernetes()
	if err != nil {
		return &pb.StatusResponse{Success: false, Error: err.Error()}, nil
	}
	if err := k8s.Stop(ctx); err != nil {
		return &pb.StatusResponse{Success: false, Error: err.Error()}, nil
	}
	return &pb.StatusResponse{Success: true, Message: "Kubernetes stopped"}, nil
}

func (s *ColimaServer) KubernetesReset(ctx context.Context, req *pb.ProfileRequest) (*pb.StatusResponse, error) {
	if err := requireProfile(req.Profile); err != nil {
		return nil, err
	}
	args := colimaProfileArgs(req.Profile, "kubernetes", "reset")
	out, err := s.execute(ctx, "colima", args...)
	if err != nil {
		return &pb.StatusResponse{Success: false, Error: commandFailure("colima", args, out, err).Error()}, nil
	}
	return &pb.StatusResponse{Success: true, Message: "Kubernetes reset"}, nil
}

func (s *ColimaServer) KubernetesExec(ctx context.Context, req *pb.KubeExecRequest) (*pb.KubeExecResponse, error) {
	args, err := shlex.Split(req.Command)
	if err != nil {
		return &pb.KubeExecResponse{Error: fmt.Sprintf("invalid kubectl command: %v", err), ExitCode: -1}, nil
	}
	if len(args) == 0 {
		return &pb.KubeExecResponse{Error: "kubectl command is required", ExitCode: -1}, nil
	}
	args = append(args, "--context", kubeContextForProfile(req.Profile))
	out, err := s.execute(ctx, "kubectl", args...)
	if ctxErr := ctx.Err(); ctxErr != nil {
		return nil, ctxErr
	}
	exitCode := 0
	if err != nil {
		exitCode = -1
		var exitErr interface{ ExitCode() int }
		if errors.As(err, &exitErr) {
			exitCode = exitErr.ExitCode()
		}
	}
	response := &pb.KubeExecResponse{Output: string(out), ExitCode: int32(exitCode)}
	if err != nil {
		response.Error = commandFailure("kubectl", args, out, err).Error()
	}
	return response, nil
}

func (s *ColimaServer) ProcessList(ctx context.Context, req *pb.ProfileRequest) (*pb.ProcessListResponse, error) {
	args := colimaProfileArgs(req.Profile, "ssh", "--", "ps", "aux", "--no-headers")
	out, err := s.execute(ctx, "colima", args...)
	if err != nil {
		return nil, commandFailure("colima", args, out, err)
	}
	processes, err := parseProcessList(string(out))
	if err != nil {
		return nil, err
	}
	return &pb.ProcessListResponse{Processes: processes}, nil
}

func parseProcessList(output string) ([]*pb.ProcessInfo, error) {
	var procs []*pb.ProcessInfo
	for lineNumber, line := range strings.Split(output, "\n") {
		if strings.TrimSpace(line) == "" {
			continue
		}
		fields := strings.Fields(line)
		if len(fields) < 11 {
			return nil, fmt.Errorf("parse process line %d: expected at least 11 fields, got %d", lineNumber+1, len(fields))
		}
		pid64, err := strconv.ParseInt(fields[1], 10, 32)
		if err != nil {
			return nil, fmt.Errorf("parse process line %d PID %q: %w", lineNumber+1, fields[1], err)
		}
		cpu, err := strconv.ParseFloat(fields[2], 64)
		if err != nil {
			return nil, fmt.Errorf("parse process line %d CPU %q: %w", lineNumber+1, fields[2], err)
		}
		memory, err := strconv.ParseFloat(fields[3], 64)
		if err != nil {
			return nil, fmt.Errorf("parse process line %d memory %q: %w", lineNumber+1, fields[3], err)
		}
		procs = append(procs, &pb.ProcessInfo{
			User:          fields[0],
			Pid:           int32(pid64),
			CpuPercent:    cpu,
			MemoryPercent: memory,
			Command:       strings.Join(fields[10:], " "),
		})
	}
	return procs, nil
}

func (s *ColimaServer) KillProcess(ctx context.Context, req *pb.KillProcessRequest) (*pb.StatusResponse, error) {
	if err := requireProfile(req.Profile); err != nil {
		return nil, err
	}
	sig := req.Signal
	if sig == 0 {
		sig = 9
	}
	args := colimaProfileArgs(req.Profile, "ssh", "--", "kill", fmt.Sprintf("-%d", sig), fmt.Sprintf("%d", req.Pid))
	out, err := s.execute(ctx, "colima", args...)
	if err != nil {
		return &pb.StatusResponse{Success: false, Error: commandFailure("colima", args, out, err).Error()}, nil
	}
	return &pb.StatusResponse{Success: true, Message: fmt.Sprintf("Process %d killed", req.Pid)}, nil
}

func (s *ColimaServer) VMStats(req *pb.ProfileRequest, stream pb.ColimaService_VMStatsServer) error {
	interval := s.statsInterval
	if interval <= 0 {
		interval = time.Second
	}
	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	var previous *vmSample
	for {
		sample, err := s.sampleVMStats(stream.Context(), req.Profile)
		if err != nil {
			if ctxErr := stream.Context().Err(); ctxErr != nil {
				return ctxErr
			}
			return err
		}
		event := sample.event(previous)
		if err := stream.Send(event); err != nil {
			return err
		}
		previous = &sample

		select {
		case <-stream.Context().Done():
			return stream.Context().Err()
		case <-ticker.C:
		}
	}
}

const vmStatsCommand = `awk '/^cpu / { idle=$5+$6; total=0; for (i=2; i<=NF; i++) total+=$i; printf "cpu %.0f %.0f\n", total, idle; exit }' /proc/stat
awk '/^MemTotal:/ { total=$2 } /^MemAvailable:/ { available=$2 } END { printf "mem %.0f %.0f\n", total, available }' /proc/meminfo
df -B1 --output=size,used / | awk 'NR==2 { printf "disk %s %s\n", $1, $2 }'
date '+time %s'`

type vmSample struct {
	cpuTotal        uint64
	cpuIdle         uint64
	memoryTotal     int64
	memoryAvailable int64
	diskTotal       int64
	diskUsed        int64
	timestamp       int64
}

func (s *ColimaServer) sampleVMStats(ctx context.Context, profile string) (vmSample, error) {
	args := colimaProfileArgs(profile, "ssh", "--", "sh", "-c", vmStatsCommand)
	out, err := s.execute(ctx, "colima", args...)
	if err != nil {
		return vmSample{}, commandFailure("colima", args, out, err)
	}
	return parseVMSample(string(out))
}

func parseVMSample(output string) (vmSample, error) {
	const maxInt64Uint = uint64(^uint64(0) >> 1)
	var sample vmSample
	seen := make(map[string]bool)
	scanner := bufio.NewScanner(strings.NewReader(output))
	for scanner.Scan() {
		fields := strings.Fields(scanner.Text())
		if len(fields) != 3 && !(len(fields) == 2 && fields[0] == "time") {
			return vmSample{}, fmt.Errorf("parse VM stats line %q", scanner.Text())
		}
		parseUint := func(value string) (uint64, error) {
			return strconv.ParseUint(value, 10, 64)
		}
		switch fields[0] {
		case "cpu":
			total, err := parseUint(fields[1])
			if err != nil {
				return vmSample{}, fmt.Errorf("parse VM CPU total: %w", err)
			}
			idle, err := parseUint(fields[2])
			if err != nil {
				return vmSample{}, fmt.Errorf("parse VM CPU idle: %w", err)
			}
			sample.cpuTotal, sample.cpuIdle = total, idle
			if idle > total {
				return vmSample{}, fmt.Errorf("VM CPU idle exceeds total")
			}
		case "mem":
			total, err := parseUint(fields[1])
			if err != nil {
				return vmSample{}, fmt.Errorf("parse VM memory total: %w", err)
			}
			available, err := parseUint(fields[2])
			if err != nil {
				return vmSample{}, fmt.Errorf("parse VM memory available: %w", err)
			}
			if total > maxInt64Uint/1024 || available > maxInt64Uint/1024 {
				return vmSample{}, fmt.Errorf("VM memory value overflows int64 bytes")
			}
			sample.memoryTotal = int64(total * 1024)
			sample.memoryAvailable = int64(available * 1024)
		case "disk":
			total, err := parseUint(fields[1])
			if err != nil {
				return vmSample{}, fmt.Errorf("parse VM disk total: %w", err)
			}
			used, err := parseUint(fields[2])
			if err != nil {
				return vmSample{}, fmt.Errorf("parse VM disk used: %w", err)
			}
			if total > maxInt64Uint || used > maxInt64Uint {
				return vmSample{}, fmt.Errorf("VM disk value overflows int64 bytes")
			}
			sample.diskTotal, sample.diskUsed = int64(total), int64(used)
		case "time":
			timestamp, err := strconv.ParseInt(fields[1], 10, 64)
			if err != nil {
				return vmSample{}, fmt.Errorf("parse VM stats timestamp: %w", err)
			}
			sample.timestamp = timestamp
		default:
			return vmSample{}, fmt.Errorf("unknown VM stats field %q", fields[0])
		}
		seen[fields[0]] = true
	}
	if err := scanner.Err(); err != nil {
		return vmSample{}, fmt.Errorf("scan VM stats: %w", err)
	}
	for _, required := range []string{"cpu", "mem", "disk", "time"} {
		if !seen[required] {
			return vmSample{}, fmt.Errorf("VM stats output missing %s", required)
		}
	}
	if sample.memoryAvailable > sample.memoryTotal {
		return vmSample{}, fmt.Errorf("VM available memory exceeds total memory")
	}
	if sample.diskUsed > sample.diskTotal {
		return vmSample{}, fmt.Errorf("VM used disk exceeds total disk")
	}
	return sample, nil
}

func (sample vmSample) event(previous *vmSample) *pb.VMStatsEvent {
	cpuPercent := 0.0
	if previous != nil && sample.cpuTotal > previous.cpuTotal {
		totalDelta := sample.cpuTotal - previous.cpuTotal
		idleDelta := uint64(0)
		if sample.cpuIdle >= previous.cpuIdle {
			idleDelta = sample.cpuIdle - previous.cpuIdle
		}
		if idleDelta <= totalDelta {
			cpuPercent = float64(totalDelta-idleDelta) / float64(totalDelta) * 100
		}
	}
	return &pb.VMStatsEvent{
		CpuPercent:  cpuPercent,
		MemoryTotal: sample.memoryTotal,
		MemoryUsed:  sample.memoryTotal - sample.memoryAvailable,
		DiskTotal:   sample.diskTotal,
		DiskUsed:    sample.diskUsed,
		Timestamp:   sample.timestamp,
	}
}

// Helpers

func configFromProto(pc *pb.ColimaConfig) config.Config {
	if pc == nil {
		return config.Config{}
	}
	return config.Config{
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
	}
}
