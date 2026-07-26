package server

import (
	"context"
	"fmt"
	"strings"

	pb "github.com/colima-desktop/daemon/proto"
)

// run executes a colima CLI command and maps the result to StatusResponse.
func (s *ColimaServer) run(ctx context.Context, args ...string) (*pb.StatusResponse, error) {
	out, err := s.execute(ctx, "colima", args...)
	if ctxErr := ctx.Err(); ctxErr != nil {
		return nil, ctxErr
	}
	result := statusFromCommand("colima", args, out, err)
	if result.err != nil {
		return &pb.StatusResponse{Success: false, Error: result.err.Error()}, nil
	}
	return &pb.StatusResponse{Success: true, Message: result.message}, nil
}

// streamCmd runs a colima command and streams combined output lines as
// ProgressEvents. Command cancellation follows the gRPC stream context.
func (s *ColimaServer) streamCmd(
	ctx context.Context,
	send func(*pb.ProgressEvent) error,
	stage string,
	args ...string,
) error {
	err := s.executeLines(ctx, "colima", args, func(line string) error {
		return send(&pb.ProgressEvent{Stage: stage, Message: line})
	})
	if err != nil {
		if ctxErr := ctx.Err(); ctxErr != nil {
			return ctxErr
		}
		if callbackErr := asLineCallbackError(err); callbackErr != nil {
			return callbackErr
		}
		message := fmt.Sprintf("colima %s: %v", strings.Join(args, " "), err)
		return send(&pb.ProgressEvent{Stage: stage, Message: message, Error: message, Done: true})
	}
	return send(&pb.ProgressEvent{Stage: stage, Progress: 1, Done: true})
}

// Profiles

func (s *ColimaServer) CreateProfile(ctx context.Context, request *pb.CreateProfileRequest) (*pb.StatusResponse, error) {
	if err := requireScopeField(request.Name, "profile name"); err != nil {
		return nil, err
	}
	args := colimaProfileArgs(request.Name, "start")
	if config := request.Config; config != nil {
		if config.Cpu > 0 {
			args = append(args, "--cpu", fmt.Sprint(config.Cpu))
		}
		if config.Memory > 0 {
			args = append(args, "--memory", fmt.Sprint(config.Memory))
		}
		if config.Disk > 0 {
			args = append(args, "--disk", fmt.Sprint(config.Disk))
		}
		if config.VmType != "" {
			args = append(args, "--vm-type", config.VmType)
		}
		if config.Runtime != "" {
			args = append(args, "--runtime", config.Runtime)
		}
	}
	return s.run(ctx, args...)
}

func (s *ColimaServer) DeleteProfile(ctx context.Context, request *pb.DeleteProfileRequest) (*pb.StatusResponse, error) {
	if err := requireScopeField(request.Name, "profile name"); err != nil {
		return nil, err
	}
	args := colimaProfileArgs(request.Name, "delete", "--force")
	if request.Data {
		args = append(args, "--data")
	}
	return s.run(ctx, args...)
}

func (s *ColimaServer) CloneProfile(ctx context.Context, request *pb.CloneProfileRequest) (*pb.StatusResponse, error) {
	if err := requireScopeField(request.Source, "clone source profile"); err != nil {
		return nil, err
	}
	if err := requireScopeField(request.Destination, "clone destination profile"); err != nil {
		return nil, err
	}
	return s.run(ctx, "clone", request.Source, request.Destination)
}

// Runtime

func (s *ColimaServer) SwitchRuntime(ctx context.Context, request *pb.SwitchRuntimeRequest) (*pb.StatusResponse, error) {
	if err := requireProfile(request.Profile); err != nil {
		return nil, err
	}
	args := colimaProfileArgs(request.Profile, "start", "--runtime", request.Runtime)
	return s.run(ctx, args...)
}

func (s *ColimaServer) UpdateRuntime(ctx context.Context, request *pb.ProfileRequest) (*pb.StatusResponse, error) {
	if err := requireProfile(request.Profile); err != nil {
		return nil, err
	}
	return s.run(ctx, colimaProfileArgs(request.Profile, "update")...)
}

// AI models

func (s *ColimaServer) ModelSetup(request *pb.ModelRequest, stream pb.ColimaService_ModelSetupServer) error {
	if err := requireProfile(request.Profile); err != nil {
		return err
	}
	runner := request.Runner
	if runner == "" {
		runner = "docker"
	}
	args := colimaProfileArgs(request.Profile, "model", "--runner", runner, "setup")
	return s.streamCmd(stream.Context(), stream.Send, "model-setup", args...)
}

func (s *ColimaServer) ModelRun(request *pb.ModelRunRequest, stream pb.ColimaService_ModelRunServer) error {
	if err := requireProfile(request.Profile); err != nil {
		return err
	}
	runner := request.Runner
	if runner == "" {
		runner = "docker"
	}
	args := colimaProfileArgs(request.Profile, "model", "--runner", runner, "run", request.Model)
	if request.Prompt != "" {
		args = append(args, request.Prompt)
	}
	return s.streamCmd(stream.Context(), stream.Send, "model-run", args...)
}

func (s *ColimaServer) ModelServe(ctx context.Context, request *pb.ModelServeRequest) (*pb.StatusResponse, error) {
	if err := requireProfile(request.Profile); err != nil {
		return nil, err
	}
	runner := request.Runner
	if runner == "" {
		runner = "docker"
	}
	args := colimaProfileArgs(request.Profile, "model", "--runner", runner, "serve")
	if request.Model != "" {
		args = append(args, request.Model)
	}
	if request.Port > 0 {
		args = append(args, "--port", fmt.Sprint(request.Port))
	}
	return s.run(ctx, args...)
}

const modelStopScript = `if ! command -v pgrep >/dev/null 2>&1 || ! command -v pkill >/dev/null 2>&1; then
  echo "pgrep and pkill are required to stop model serve processes" >&2
  exit 20
fi
model_ip=""
if command -v docker >/dev/null 2>&1 && [ "$(docker inspect docker-model-runner --format '{{.State.Running}}' 2>/dev/null || true)" = "true" ]; then
  model_ip="$(docker inspect docker-model-runner --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null || true)"
  if ! docker exec docker-model-runner sh -c "command -v pgrep >/dev/null 2>&1 && command -v pkill >/dev/null 2>&1"; then
    echo "docker-model-runner lacks pgrep or pkill" >&2
    exit 21
  fi
  if docker exec docker-model-runner sh -c "pgrep -f '[c]om.docker.llama-server'" >/dev/null 2>&1; then
    docker exec docker-model-runner sh -c "pkill -TERM -f '[c]om.docker.llama-server'" >/dev/null 2>&1 || exit 22
  fi
  if [ -n "$model_ip" ]; then
    if pgrep -f "[s]ocat.*TCP:${model_ip}:" >/dev/null 2>&1; then
      pkill -TERM -f "[s]ocat.*TCP:${model_ip}:" >/dev/null 2>&1 || exit 23
    fi
  fi
fi
if pgrep -f '[r]amalama serve' >/dev/null 2>&1; then
  pkill -TERM -f '[r]amalama serve' >/dev/null 2>&1 || exit 24
fi
exit 0`

func (s *ColimaServer) ModelStop(ctx context.Context, request *pb.ProfileRequest) (*pb.StatusResponse, error) {
	if err := requireProfile(request.Profile); err != nil {
		return nil, err
	}
	args := colimaProfileArgs(request.Profile, "ssh", "--", "sh", "-c", modelStopScript)
	response, err := s.run(ctx, args...)
	if err == nil && response.Success {
		response.Message = "all model serve processes for the profile were stopped if running"
	}
	return response, err
}
