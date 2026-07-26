// Package client wraps the colima-desktop daemon gRPC services for the TUI.
package client

import (
	"context"
	"errors"
	"fmt"
	"io"
	"runtime"
	"strings"
	"time"

	pb "github.com/colima-desktop/daemon/proto"
	"github.com/colima-desktop/tui/internal/action"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

// Client connects to the local daemon over its unix socket and exposes the
// ColimaService + DockerService contracts.
type Client struct {
	conn   *grpc.ClientConn
	Colima pb.ColimaServiceClient
	Docker pb.DockerServiceClient
}

// DefaultEndpoint matches the daemon's native listener defaults.
func DefaultEndpoint() string {
	if runtime.GOOS == "windows" {
		return "tcp:127.0.0.1:50051"
	}
	return "unix:/tmp/colima-desktop.sock"
}

// Dial connects to a daemon Unix socket or loopback TCP listener. Accepted
// forms include /path, unix:/path, host:port, tcp:host:port, and tcp://host:port.
func Dial(endpoint string) (*Client, error) {
	target, err := normalizeEndpoint(endpoint)
	if err != nil {
		return nil, err
	}
	conn, err := grpc.NewClient(
		target,
		grpc.WithTransportCredentials(insecure.NewCredentials()),
	)
	if err != nil {
		return nil, err
	}
	return &Client{
		conn:   conn,
		Colima: pb.NewColimaServiceClient(conn),
		Docker: pb.NewDockerServiceClient(conn),
	}, nil
}

func normalizeEndpoint(endpoint string) (string, error) {
	endpoint = strings.TrimSpace(endpoint)
	if endpoint == "" {
		return "", errors.New("daemon endpoint is empty")
	}
	if strings.HasPrefix(endpoint, "unix:") {
		path := strings.TrimPrefix(endpoint, "unix:")
		path = strings.TrimPrefix(path, "//")
		if path == "" {
			return "", errors.New("daemon Unix socket path is empty")
		}
		return "unix://" + path, nil
	}
	if strings.HasPrefix(endpoint, "/") {
		return "unix://" + endpoint, nil
	}
	if strings.HasPrefix(endpoint, "tcp:") {
		endpoint = strings.TrimPrefix(endpoint, "tcp:")
		endpoint = strings.TrimPrefix(endpoint, "//")
	}
	if endpoint == "" {
		return "", errors.New("daemon TCP address is empty")
	}
	return endpoint, nil
}

// Close releases the gRPC connection.
func (c *Client) Close() error { return c.conn.Close() }

func ctx() (context.Context, context.CancelFunc) {
	return context.WithTimeout(context.Background(), 15*time.Second)
}

// ─── ColimaService methods ───────────────────────────────────────────────────

// Status returns the current VM status for the profile.
func (c *Client) Status(profile string) (*pb.VMStatus, error) {
	cx, cancel := ctx()
	defer cancel()
	return c.Colima.Status(cx, &pb.StatusRequest{Profile: profile})
}

// Profiles lists all colima profiles.
func (c *Client) Profiles() (*pb.ProfileList, error) {
	cx, cancel := ctx()
	defer cancel()
	return c.Colima.ListProfiles(cx, &pb.Empty{})
}

// Machines lists Lima VMs.
func (c *Client) Machines() (*pb.MachineList, error) {
	cx, cancel := ctx()
	defer cancel()
	return c.Colima.ListMachines(cx, &pb.Empty{})
}

// GetConfig fetches the colima configuration for a profile.
func (c *Client) GetConfig(profile string) (*pb.ColimaConfig, error) {
	cx, cancel := ctx()
	defer cancel()
	return c.Colima.GetConfig(cx, &pb.ProfileRequest{Profile: profile})
}

// GetTemplate fetches the global typed Colima configuration template. The v1
// protobuf intentionally does not scope templates to a profile.
func (c *Client) GetTemplate() (*pb.ColimaConfig, error) {
	cx, cancel := ctx()
	defer cancel()
	return c.Colima.GetTemplate(cx, &pb.Empty{})
}

// KubernetesStatus returns the VM status (which includes the kubernetes field)
// for the given profile — used to display Kubernetes state.
func (c *Client) KubernetesStatus(profile string) (*pb.VMStatus, error) {
	cx, cancel := ctx()
	defer cancel()
	return c.Colima.Status(cx, &pb.StatusRequest{Profile: profile})
}

// VMStats reads one sample from the VMStats stream (bounded: reads until first
// message or timeout, then cancels the stream). Returns nil if unimplemented.
func (c *Client) VMStats(profile string) (*pb.VMStatsEvent, error) {
	cx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	stream, err := c.Colima.VMStats(cx, &pb.ProfileRequest{Profile: profile})
	if err != nil {
		return nil, err
	}
	evt, err := stream.Recv()
	if err != nil && err != io.EOF {
		return nil, err
	}
	return evt, nil
}

// ProcessList returns the process list for the given profile.
func (c *Client) ProcessList(profile string) (*pb.ProcessListResponse, error) {
	cx, cancel := ctx()
	defer cancel()
	return c.Colima.ProcessList(cx, &pb.ProfileRequest{Profile: profile})
}

// RunAction maps a typed TUI request to exactly one unary protobuf RPC. It
// treats application-level failure fields as errors; a successful transport is
// not presented as a successful operation unless the daemon confirms it.
func (c *Client) RunAction(cx context.Context, req action.Request) (action.Result, error) {
	var (
		status *pb.StatusResponse
		json   *pb.JsonResponse
		err    error
	)

	switch req.Kind {
	case action.VMStop:
		status, err = c.Colima.Stop(cx, &pb.StopRequest{Profile: req.Profile, Force: req.Force})
	case action.VMDelete:
		status, err = c.Colima.Delete(cx, &pb.DeleteRequest{Profile: req.Profile, Data: req.Data, Force: req.Force})
	case action.VMUpdate:
		status, err = c.Colima.Update(cx, &pb.ProfileRequest{Profile: req.Profile})
	case action.VMPrune:
		status, err = c.Colima.Prune(cx, &pb.PruneRequest{All: req.All, Profile: req.Profile})
	case action.VMSSHConfig:
		var response *pb.SSHConfigResponse
		response, err = c.Colima.SSHConfig(cx, &pb.ProfileRequest{Profile: req.Profile})
		if err == nil {
			return action.Result{Text: response.GetConfig()}, nil
		}
	case action.ContainerDo:
		status, err = c.Docker.ContainerAction(cx, &pb.ContainerActionRequest{
			Id: req.ID, Action: req.Action, Profile: req.Profile, Host: req.Host, Wsl2: req.WSL2,
		})
	case action.ContainerNew:
		json, err = c.Docker.CreateContainer(cx, &pb.CreateContainerRequest{
			Name: req.Name, Image: req.Target, Profile: req.Profile, Host: req.Host, Wsl2: req.WSL2,
		})
	case action.ContainerName:
		status, err = c.Docker.RenameContainer(cx, &pb.RenameRequest{
			Id: req.ID, NewName: req.NewName, Profile: req.Profile, Host: req.Host, Wsl2: req.WSL2,
		})
	case action.ContainerLogs:
		json, err = c.Docker.ContainerLogs(cx, idRequest(req))
	case action.ContainerInfo:
		json, err = c.Docker.InspectContainer(cx, idRequest(req))
	case action.ContainerTop:
		json, err = c.Docker.ContainerTop(cx, idRequest(req))
	case action.ContainerStat:
		json, err = c.Docker.ContainerStats(cx, idRequest(req))
	case action.ContainerDiff:
		json, err = c.Docker.ContainerChanges(cx, idRequest(req))
	case action.ContainerPrune:
		json, err = c.Docker.PruneContainers(cx, &pb.DockerScope{Profile: req.Profile, All: req.All, Host: req.Host, Wsl2: req.WSL2})
	case action.ImageRemove:
		status, err = c.Docker.RemoveImage(cx, idRequest(req))
	case action.ImageInspect:
		json, err = c.Docker.InspectImage(cx, nameRequest(req))
	case action.ImageHistory:
		json, err = c.Docker.ImageHistory(cx, nameRequest(req))
	case action.ImageTag:
		status, err = c.Docker.TagImage(cx, &pb.TagRequest{
			Name: req.Name, Repo: req.Repository, Tag: req.Tag, Profile: req.Profile, Host: req.Host, Wsl2: req.WSL2,
		})
	case action.ImageSearch:
		json, err = c.Docker.SearchImages(cx, &pb.SearchRequest{Term: req.Term, Profile: req.Profile, Host: req.Host, Wsl2: req.WSL2})
	case action.ImagePrune:
		json, err = c.Docker.PruneImages(cx, &pb.DockerScope{Profile: req.Profile, All: req.All, Host: req.Host, Wsl2: req.WSL2})
	case action.VolumeCreate:
		json, err = c.Docker.CreateVolume(cx, nameRequest(req))
	case action.VolumeRemove:
		status, err = c.Docker.RemoveVolume(cx, nameRequest(req))
	case action.VolumeInspect:
		json, err = c.Docker.InspectVolume(cx, nameRequest(req))
	case action.VolumePrune:
		json, err = c.Docker.PruneVolumes(cx, &pb.DockerScope{Profile: req.Profile, All: req.All, Host: req.Host, Wsl2: req.WSL2})
	case action.NetworkCreate:
		json, err = c.Docker.CreateNetwork(cx, nameRequest(req))
	case action.NetworkRemove:
		status, err = c.Docker.RemoveNetwork(cx, idRequest(req))
	case action.NetworkInspect:
		json, err = c.Docker.InspectNetwork(cx, idRequest(req))
	case action.NetworkConnect:
		status, err = c.Docker.ConnectNetwork(cx, &pb.NetworkContainerRequest{
			NetworkId: req.ID, ContainerId: req.ContainerID, Profile: req.Profile, Host: req.Host, Wsl2: req.WSL2,
		})
	case action.NetworkDisconnect:
		status, err = c.Docker.DisconnectNetwork(cx, &pb.NetworkContainerRequest{
			NetworkId: req.ID, ContainerId: req.ContainerID, Profile: req.Profile, Host: req.Host, Wsl2: req.WSL2,
		})
	case action.NetworkPrune:
		json, err = c.Docker.PruneNetworks(cx, &pb.DockerScope{Profile: req.Profile, All: req.All, Host: req.Host, Wsl2: req.WSL2})
	case action.KubeStart:
		status, err = c.Colima.KubernetesStart(cx, &pb.ProfileRequest{Profile: req.Profile})
	case action.KubeStop:
		status, err = c.Colima.KubernetesStop(cx, &pb.ProfileRequest{Profile: req.Profile})
	case action.KubeReset:
		status, err = c.Colima.KubernetesReset(cx, &pb.ProfileRequest{Profile: req.Profile})
	case action.KubeExec:
		var response *pb.KubeExecResponse
		response, err = c.Colima.KubernetesExec(cx, &pb.KubeExecRequest{Profile: req.Profile, Command: req.Command})
		if err == nil {
			if response.GetError() != "" || response.GetExitCode() != 0 {
				return action.Result{}, fmt.Errorf("kubectl exit %d: %s", response.GetExitCode(), or(response.GetError(), response.GetOutput()))
			}
			return action.Result{Text: response.GetOutput()}, nil
		}
	case action.ProfileCreate:
		status, err = c.Colima.CreateProfile(cx, &pb.CreateProfileRequest{Name: req.Name, Config: req.Config})
	case action.ProfileDelete:
		status, err = c.Colima.DeleteProfile(cx, &pb.DeleteProfileRequest{Name: req.Name, Data: req.Data, Force: req.Force})
	case action.ProfileClone:
		status, err = c.Colima.CloneProfile(cx, &pb.CloneProfileRequest{Source: req.Source, Destination: req.Target})
	case action.ConfigSet:
		status, err = c.Colima.SetConfig(cx, &pb.SetConfigRequest{Profile: req.Profile, Config: req.Config})
	case action.TemplateSet:
		status, err = c.Colima.SetTemplate(cx, req.Config)
	case action.RuntimeSwitch:
		status, err = c.Colima.SwitchRuntime(cx, &pb.SwitchRuntimeRequest{Profile: req.Profile, Runtime: req.Runtime})
	case action.RuntimeUpdate:
		status, err = c.Colima.UpdateRuntime(cx, &pb.ProfileRequest{Profile: req.Profile})
	case action.ModelServe:
		status, err = c.Colima.ModelServe(cx, &pb.ModelServeRequest{
			Profile: req.Profile, Model: req.Model, Runner: req.Runner, Port: req.Port,
		})
	case action.ModelStop:
		status, err = c.Colima.ModelStop(cx, &pb.ProfileRequest{Profile: req.Profile})
	case action.ProcessKill:
		status, err = c.Colima.KillProcess(cx, &pb.KillProcessRequest{
			Profile: req.Profile, Pid: req.PID, Signal: req.Signal,
		})
	default:
		return action.Result{}, fmt.Errorf("unsupported unary action %q", req.Kind)
	}

	if err != nil {
		return action.Result{}, err
	}
	if status != nil {
		return statusResult(status)
	}
	if json != nil {
		if json.GetError() != "" {
			return action.Result{}, errors.New(json.GetError())
		}
		return action.Result{Text: json.GetJson()}, nil
	}
	return action.Result{}, errors.New("daemon returned no response")
}

// OpenProgress maps the six progress-producing TUI actions to their generated
// streaming RPC. The caller owns cancellation through cx.
func (c *Client) OpenProgress(cx context.Context, req action.Request) (action.ProgressStream, error) {
	switch req.Kind {
	case action.VMStart:
		if req.Config == nil {
			config, err := c.Colima.GetConfig(cx, &pb.ProfileRequest{Profile: req.Profile})
			if err != nil {
				return nil, fmt.Errorf("load profile config before start: %w", err)
			}
			req.Config = config
		}
		return c.Colima.Start(cx, &pb.StartRequest{Profile: req.Profile, Config: req.Config})
	case action.VMRestart:
		return c.Colima.Restart(cx, &pb.RestartRequest{Profile: req.Profile})
	case action.ImagePull:
		return c.Docker.PullImage(cx, nameRequest(req))
	case action.ImagePush:
		return c.Docker.PushImage(cx, nameRequest(req))
	case action.ModelSetup:
		return c.Colima.ModelSetup(cx, &pb.ModelRequest{Profile: req.Profile, Runner: req.Runner})
	case action.ModelRun:
		return c.Colima.ModelRun(cx, &pb.ModelRunRequest{
			Profile: req.Profile, Model: req.Model, Runner: req.Runner, Prompt: req.Prompt,
		})
	default:
		return nil, fmt.Errorf("unsupported streaming action %q", req.Kind)
	}
}

func idRequest(req action.Request) *pb.IdRequest {
	return &pb.IdRequest{Id: req.ID, Profile: req.Profile, Host: req.Host, Wsl2: req.WSL2}
}

func nameRequest(req action.Request) *pb.NameRequest {
	name := req.Name
	if name == "" {
		name = req.ID
	}
	return &pb.NameRequest{Name: name, Profile: req.Profile, Host: req.Host, Wsl2: req.WSL2}
}

func statusResult(response *pb.StatusResponse) (action.Result, error) {
	if response == nil {
		return action.Result{}, errors.New("daemon returned an empty status")
	}
	if !response.GetSuccess() {
		return action.Result{}, errors.New(or(response.GetError(), or(response.GetMessage(), "operation was not confirmed successful")))
	}
	return action.Result{Text: or(response.GetMessage(), "completed")}, nil
}

func or(value, fallback string) string {
	if strings.TrimSpace(value) == "" {
		return fallback
	}
	return value
}

// ─── DockerService methods ───────────────────────────────────────────────────

// Containers returns raw Docker JSON for the profile.
func (c *Client) Containers(profile string) (string, error) {
	cx, cancel := ctx()
	defer cancel()
	r, err := c.Docker.ListContainers(cx, &pb.DockerScope{Profile: profile, All: true})
	if err != nil {
		return "", err
	}
	if r.Error != "" {
		return "", &apiError{r.Error}
	}
	return r.Json, nil
}

// Images returns raw Docker JSON for the profile.
func (c *Client) Images(profile string) (string, error) {
	cx, cancel := ctx()
	defer cancel()
	r, err := c.Docker.ListImages(cx, &pb.DockerScope{Profile: profile})
	if err != nil {
		return "", err
	}
	if r.Error != "" {
		return "", &apiError{r.Error}
	}
	return r.Json, nil
}

// Volumes returns raw Docker JSON for volumes in the profile.
func (c *Client) Volumes(profile string) (string, error) {
	cx, cancel := ctx()
	defer cancel()
	r, err := c.Docker.ListVolumes(cx, &pb.DockerScope{Profile: profile})
	if err != nil {
		return "", err
	}
	if r.Error != "" {
		return "", &apiError{r.Error}
	}
	return r.Json, nil
}

// Networks returns raw Docker JSON for networks in the profile.
func (c *Client) Networks(profile string) (string, error) {
	cx, cancel := ctx()
	defer cancel()
	r, err := c.Docker.ListNetworks(cx, &pb.DockerScope{Profile: profile})
	if err != nil {
		return "", err
	}
	if r.Error != "" {
		return "", &apiError{r.Error}
	}
	return r.Json, nil
}

type apiError struct{ msg string }

func (e *apiError) Error() string { return e.msg }
