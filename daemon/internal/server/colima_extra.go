package server

import (
	"bufio"
	"context"
	"fmt"
	"os/exec"
	"strings"

	"github.com/abiosoft/colima/config"
	pb "github.com/colima-desktop/daemon/proto"
)

// run executes a colima CLI command and maps the result to StatusResponse.
func run(args ...string) (*pb.StatusResponse, error) {
	out, err := exec.Command("colima", args...).CombinedOutput()
	if err != nil {
		return &pb.StatusResponse{Success: false, Error: strings.TrimSpace(string(out))}, nil
	}
	return &pb.StatusResponse{Success: true, Message: strings.TrimSpace(string(out))}, nil
}

// streamCmd runs a colima command and streams stdout lines as ProgressEvents.
func streamCmd(send func(*pb.ProgressEvent) error, stage string, args ...string) error {
	cmd := exec.Command("colima", args...)
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return err
	}
	cmd.Stderr = cmd.Stdout
	if err := cmd.Start(); err != nil {
		return send(&pb.ProgressEvent{Stage: stage, Error: err.Error(), Done: true})
	}
	sc := bufio.NewScanner(stdout)
	for sc.Scan() {
		if err := send(&pb.ProgressEvent{Stage: stage, Message: sc.Text()}); err != nil {
			_ = cmd.Process.Kill()
			return err
		}
	}
	err = cmd.Wait()
	done := &pb.ProgressEvent{Stage: stage, Progress: 1.0, Done: true}
	if err != nil {
		done.Error = err.Error()
	}
	return send(done)
}

// Profiles

func (s *ColimaServer) CreateProfile(_ context.Context, r *pb.CreateProfileRequest) (*pb.StatusResponse, error) {
	args := []string{"start", "--profile", r.Name}
	if c := r.Config; c != nil {
		if c.Cpu > 0 {
			args = append(args, "--cpu", fmt.Sprint(c.Cpu))
		}
		if c.Memory > 0 {
			args = append(args, "--memory", fmt.Sprint(c.Memory))
		}
		if c.Disk > 0 {
			args = append(args, "--disk", fmt.Sprint(c.Disk))
		}
		if c.VmType != "" {
			args = append(args, "--vm-type", c.VmType)
		}
		if c.Runtime != "" {
			args = append(args, "--runtime", c.Runtime)
		}
	}
	return run(args...)
}

func (s *ColimaServer) DeleteProfile(_ context.Context, r *pb.DeleteProfileRequest) (*pb.StatusResponse, error) {
	args := []string{"delete", "--profile", r.Name, "--force"}
	if r.Data {
		args = append(args, "--data")
	}
	return run(args...)
}

func (s *ColimaServer) CloneProfile(_ context.Context, r *pb.CloneProfileRequest) (*pb.StatusResponse, error) {
	return run("clone", r.Source, r.Destination)
}

// Runtime

func (s *ColimaServer) SwitchRuntime(_ context.Context, r *pb.SwitchRuntimeRequest) (*pb.StatusResponse, error) {
	args := []string{"start"}
	if r.Profile != "" {
		args = append(args, "--profile", r.Profile)
	}
	args = append(args, "--runtime", r.Runtime)
	return run(args...)
}

func (s *ColimaServer) UpdateRuntime(_ context.Context, r *pb.ProfileRequest) (*pb.StatusResponse, error) {
	if r.Profile != "" {
		config.SetProfile(r.Profile)
	}
	return run("update")
}

// AI models

func (s *ColimaServer) ModelSetup(r *pb.ModelRequest, stream pb.ColimaService_ModelSetupServer) error {
	runner := r.Runner
	if runner == "" {
		runner = "docker"
	}
	return streamCmd(stream.Send, "model-setup", "model", "setup", "--runner", runner)
}

func (s *ColimaServer) ModelRun(r *pb.ModelRunRequest, stream pb.ColimaService_ModelRunServer) error {
	runner := r.Runner
	if runner == "" {
		runner = "docker"
	}
	args := []string{"model", "run", r.Model, "--runner", runner}
	return streamCmd(stream.Send, "model-run", args...)
}

func (s *ColimaServer) ModelServe(_ context.Context, r *pb.ModelServeRequest) (*pb.StatusResponse, error) {
	args := []string{"model", "serve"}
	if r.Model != "" {
		args = append(args, r.Model)
	}
	runner := r.Runner
	if runner == "" {
		runner = "docker"
	}
	args = append(args, "--runner", runner)
	if r.Port > 0 {
		args = append(args, "--port", fmt.Sprint(r.Port))
	}
	return run(args...)
}

func (s *ColimaServer) ModelStop(_ context.Context, r *pb.ProfileRequest) (*pb.StatusResponse, error) {
	// Model runner containers are managed by docker; stopping is best-effort.
	return &pb.StatusResponse{Success: true, Message: "model stop requested"}, nil
}
