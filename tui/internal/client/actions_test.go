package client

import (
	"context"
	"net"
	"strings"
	"sync"
	"testing"
	"time"

	pb "github.com/colima-desktop/daemon/proto"
	"github.com/colima-desktop/tui/internal/action"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/grpc/test/bufconn"
	"google.golang.org/protobuf/proto"
)

type recordingServer struct {
	pb.UnimplementedColimaServiceServer
	pb.UnimplementedDockerServiceServer

	mu       sync.Mutex
	method   string
	request  proto.Message
	failNext bool
}

func (s *recordingServer) record(method string, request proto.Message) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.method = method
	s.request = proto.Clone(request)
}

func (s *recordingServer) status(method string, request proto.Message) (*pb.StatusResponse, error) {
	s.mu.Lock()
	s.method = method
	s.request = proto.Clone(request)
	fail := s.failNext
	s.failNext = false
	s.mu.Unlock()
	if fail {
		return &pb.StatusResponse{Success: false, Error: "daemon refused action"}, nil
	}
	return &pb.StatusResponse{Success: true, Message: "done"}, nil
}

func (s *recordingServer) Stop(_ context.Context, request *pb.StopRequest) (*pb.StatusResponse, error) {
	return s.status("Stop", request)
}

func (s *recordingServer) Delete(_ context.Context, request *pb.DeleteRequest) (*pb.StatusResponse, error) {
	return s.status("Delete", request)
}

func (s *recordingServer) Update(_ context.Context, request *pb.ProfileRequest) (*pb.StatusResponse, error) {
	return s.status("Update", request)
}

func (s *recordingServer) Prune(_ context.Context, request *pb.PruneRequest) (*pb.StatusResponse, error) {
	return s.status("Prune", request)
}

func (s *recordingServer) SSHConfig(_ context.Context, request *pb.ProfileRequest) (*pb.SSHConfigResponse, error) {
	s.record("SSHConfig", request)
	return &pb.SSHConfigResponse{Config: "Host colima"}, nil
}

func (s *recordingServer) CreateProfile(_ context.Context, request *pb.CreateProfileRequest) (*pb.StatusResponse, error) {
	return s.status("CreateProfile", request)
}

func (s *recordingServer) DeleteProfile(_ context.Context, request *pb.DeleteProfileRequest) (*pb.StatusResponse, error) {
	return s.status("DeleteProfile", request)
}

func (s *recordingServer) CloneProfile(_ context.Context, request *pb.CloneProfileRequest) (*pb.StatusResponse, error) {
	return s.status("CloneProfile", request)
}

func (s *recordingServer) SetConfig(_ context.Context, request *pb.SetConfigRequest) (*pb.StatusResponse, error) {
	return s.status("SetConfig", request)
}

func (s *recordingServer) GetConfig(_ context.Context, request *pb.ProfileRequest) (*pb.ColimaConfig, error) {
	s.record("GetConfig", request)
	return &pb.ColimaConfig{Cpu: 7, Memory: 12, Runtime: "docker"}, nil
}

func (s *recordingServer) SetTemplate(_ context.Context, request *pb.ColimaConfig) (*pb.StatusResponse, error) {
	return s.status("SetTemplate", request)
}

func (s *recordingServer) KubernetesStart(_ context.Context, request *pb.ProfileRequest) (*pb.StatusResponse, error) {
	return s.status("KubernetesStart", request)
}

func (s *recordingServer) KubernetesStop(_ context.Context, request *pb.ProfileRequest) (*pb.StatusResponse, error) {
	return s.status("KubernetesStop", request)
}

func (s *recordingServer) KubernetesReset(_ context.Context, request *pb.ProfileRequest) (*pb.StatusResponse, error) {
	return s.status("KubernetesReset", request)
}

func (s *recordingServer) SwitchRuntime(_ context.Context, request *pb.SwitchRuntimeRequest) (*pb.StatusResponse, error) {
	return s.status("SwitchRuntime", request)
}

func (s *recordingServer) UpdateRuntime(_ context.Context, request *pb.ProfileRequest) (*pb.StatusResponse, error) {
	return s.status("UpdateRuntime", request)
}

func (s *recordingServer) ModelServe(_ context.Context, request *pb.ModelServeRequest) (*pb.StatusResponse, error) {
	return s.status("ModelServe", request)
}

func (s *recordingServer) ModelStop(_ context.Context, request *pb.ProfileRequest) (*pb.StatusResponse, error) {
	return s.status("ModelStop", request)
}

func (s *recordingServer) KillProcess(_ context.Context, request *pb.KillProcessRequest) (*pb.StatusResponse, error) {
	return s.status("KillProcess", request)
}

func (s *recordingServer) KubernetesExec(_ context.Context, request *pb.KubeExecRequest) (*pb.KubeExecResponse, error) {
	s.record("KubernetesExec", request)
	return &pb.KubeExecResponse{Output: "pod-a", ExitCode: 0}, nil
}

func (s *recordingServer) ContainerAction(_ context.Context, request *pb.ContainerActionRequest) (*pb.StatusResponse, error) {
	return s.status("ContainerAction", request)
}

func (s *recordingServer) RenameContainer(_ context.Context, request *pb.RenameRequest) (*pb.StatusResponse, error) {
	return s.status("RenameContainer", request)
}

func (s *recordingServer) json(method string, request proto.Message) (*pb.JsonResponse, error) {
	s.record(method, request)
	return &pb.JsonResponse{Json: `{"ok":true}`}, nil
}

func (s *recordingServer) CreateContainer(_ context.Context, request *pb.CreateContainerRequest) (*pb.JsonResponse, error) {
	return s.json("CreateContainer", request)
}

func (s *recordingServer) ContainerLogs(_ context.Context, request *pb.IdRequest) (*pb.JsonResponse, error) {
	return s.json("ContainerLogs", request)
}

func (s *recordingServer) InspectContainer(_ context.Context, request *pb.IdRequest) (*pb.JsonResponse, error) {
	return s.json("InspectContainer", request)
}

func (s *recordingServer) ContainerTop(_ context.Context, request *pb.IdRequest) (*pb.JsonResponse, error) {
	return s.json("ContainerTop", request)
}

func (s *recordingServer) ContainerStats(_ context.Context, request *pb.IdRequest) (*pb.JsonResponse, error) {
	return s.json("ContainerStats", request)
}

func (s *recordingServer) ContainerChanges(_ context.Context, request *pb.IdRequest) (*pb.JsonResponse, error) {
	return s.json("ContainerChanges", request)
}

func (s *recordingServer) PruneContainers(_ context.Context, request *pb.DockerScope) (*pb.JsonResponse, error) {
	return s.json("PruneContainers", request)
}

func (s *recordingServer) RemoveImage(_ context.Context, request *pb.IdRequest) (*pb.StatusResponse, error) {
	return s.status("RemoveImage", request)
}

func (s *recordingServer) InspectImage(_ context.Context, request *pb.NameRequest) (*pb.JsonResponse, error) {
	return s.json("InspectImage", request)
}

func (s *recordingServer) ImageHistory(_ context.Context, request *pb.NameRequest) (*pb.JsonResponse, error) {
	return s.json("ImageHistory", request)
}

func (s *recordingServer) TagImage(_ context.Context, request *pb.TagRequest) (*pb.StatusResponse, error) {
	return s.status("TagImage", request)
}

func (s *recordingServer) SearchImages(_ context.Context, request *pb.SearchRequest) (*pb.JsonResponse, error) {
	return s.json("SearchImages", request)
}

func (s *recordingServer) PruneImages(_ context.Context, request *pb.DockerScope) (*pb.JsonResponse, error) {
	return s.json("PruneImages", request)
}

func (s *recordingServer) CreateVolume(_ context.Context, request *pb.NameRequest) (*pb.JsonResponse, error) {
	return s.json("CreateVolume", request)
}

func (s *recordingServer) RemoveVolume(_ context.Context, request *pb.NameRequest) (*pb.StatusResponse, error) {
	return s.status("RemoveVolume", request)
}

func (s *recordingServer) InspectVolume(_ context.Context, request *pb.NameRequest) (*pb.JsonResponse, error) {
	return s.json("InspectVolume", request)
}

func (s *recordingServer) PruneVolumes(_ context.Context, request *pb.DockerScope) (*pb.JsonResponse, error) {
	return s.json("PruneVolumes", request)
}

func (s *recordingServer) CreateNetwork(_ context.Context, request *pb.NameRequest) (*pb.JsonResponse, error) {
	return s.json("CreateNetwork", request)
}

func (s *recordingServer) RemoveNetwork(_ context.Context, request *pb.IdRequest) (*pb.StatusResponse, error) {
	return s.status("RemoveNetwork", request)
}

func (s *recordingServer) InspectNetwork(_ context.Context, request *pb.IdRequest) (*pb.JsonResponse, error) {
	return s.json("InspectNetwork", request)
}

func (s *recordingServer) ConnectNetwork(_ context.Context, request *pb.NetworkContainerRequest) (*pb.StatusResponse, error) {
	return s.status("ConnectNetwork", request)
}

func (s *recordingServer) DisconnectNetwork(_ context.Context, request *pb.NetworkContainerRequest) (*pb.StatusResponse, error) {
	return s.status("DisconnectNetwork", request)
}

func (s *recordingServer) PruneNetworks(_ context.Context, request *pb.DockerScope) (*pb.JsonResponse, error) {
	return s.json("PruneNetworks", request)
}

func (s *recordingServer) Start(request *pb.StartRequest, stream pb.ColimaService_StartServer) error {
	s.record("Start", request)
	return stream.Send(&pb.ProgressEvent{Stage: "ready", Message: "started", Progress: 1, Done: true})
}

func (s *recordingServer) Restart(request *pb.RestartRequest, stream pb.ColimaService_RestartServer) error {
	s.record("Restart", request)
	return stream.Send(&pb.ProgressEvent{Stage: "ready", Message: "restarted", Progress: 1, Done: true})
}

func (s *recordingServer) PullImage(request *pb.NameRequest, stream pb.DockerService_PullImageServer) error {
	s.record("PullImage", request)
	return stream.Send(&pb.ProgressEvent{Stage: "ready", Message: "pulled", Progress: 1, Done: true})
}

func (s *recordingServer) PushImage(request *pb.NameRequest, stream pb.DockerService_PushImageServer) error {
	s.record("PushImage", request)
	return stream.Send(&pb.ProgressEvent{Stage: "ready", Message: "pushed", Progress: 1, Done: true})
}

func (s *recordingServer) ModelSetup(request *pb.ModelRequest, stream pb.ColimaService_ModelSetupServer) error {
	s.record("ModelSetup", request)
	return stream.Send(&pb.ProgressEvent{Stage: "ready", Message: "setup", Progress: 1, Done: true})
}

func (s *recordingServer) ModelRun(request *pb.ModelRunRequest, stream pb.ColimaService_ModelRunServer) error {
	s.record("ModelRun", request)
	return stream.Send(&pb.ProgressEvent{Stage: "ready", Message: "answer", Progress: 1, Done: true})
}

func newBufClient(t *testing.T) (*Client, *recordingServer) {
	t.Helper()
	listener := bufconn.Listen(1024 * 1024)
	server := grpc.NewServer()
	recorder := &recordingServer{}
	pb.RegisterColimaServiceServer(server, recorder)
	pb.RegisterDockerServiceServer(server, recorder)
	go func() { _ = server.Serve(listener) }()
	t.Cleanup(server.Stop)
	t.Cleanup(func() { _ = listener.Close() })

	conn, err := grpc.NewClient(
		"passthrough:///bufnet",
		grpc.WithContextDialer(func(context.Context, string) (net.Conn, error) { return listener.Dial() }),
		grpc.WithTransportCredentials(insecure.NewCredentials()),
	)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = conn.Close() })
	return &Client{conn: conn, Colima: pb.NewColimaServiceClient(conn), Docker: pb.NewDockerServiceClient(conn)}, recorder
}

func TestRunActionExactRPCPayloads(t *testing.T) {
	client, recorder := newBufClient(t)
	config := &pb.ColimaConfig{Cpu: 6, Memory: 8, Runtime: "containerd"}
	tests := []struct {
		name    string
		request action.Request
		method  string
		want    proto.Message
	}{
		{"stop", action.Request{Kind: action.VMStop, Profile: "desktop-e2e", Force: true}, "Stop", &pb.StopRequest{Profile: "desktop-e2e", Force: true}},
		{"delete", action.Request{Kind: action.VMDelete, Profile: "throwaway", Data: true, Force: true}, "Delete", &pb.DeleteRequest{Profile: "throwaway", Data: true, Force: true}},
		{"update", action.Request{Kind: action.VMUpdate, Profile: "desktop-e2e"}, "Update", &pb.ProfileRequest{Profile: "desktop-e2e"}},
		{"prune", action.Request{Kind: action.VMPrune, Profile: "desktop-e2e", All: true}, "Prune", &pb.PruneRequest{Profile: "desktop-e2e", All: true}},
		{"ssh", action.Request{Kind: action.VMSSHConfig, Profile: "desktop-e2e"}, "SSHConfig", &pb.ProfileRequest{Profile: "desktop-e2e"}},
		{"container", action.Request{Kind: action.ContainerDo, Profile: "desktop-e2e", ID: "ctr-123", Action: "pause"}, "ContainerAction", &pb.ContainerActionRequest{Profile: "desktop-e2e", Id: "ctr-123", Action: "pause"}},
		{"create container", action.Request{Kind: action.ContainerNew, Profile: "desktop-e2e", Name: "web", Target: "nginx:latest"}, "CreateContainer", &pb.CreateContainerRequest{Profile: "desktop-e2e", Name: "web", Image: "nginx:latest"}},
		{"rename", action.Request{Kind: action.ContainerName, Profile: "desktop-e2e", Host: "user@host", ID: "ctr-123", NewName: "api-v2"}, "RenameContainer", &pb.RenameRequest{Profile: "desktop-e2e", Host: "user@host", Id: "ctr-123", NewName: "api-v2"}},
		{"container logs", action.Request{Kind: action.ContainerLogs, Profile: "desktop-e2e", ID: "ctr-123"}, "ContainerLogs", &pb.IdRequest{Profile: "desktop-e2e", Id: "ctr-123"}},
		{"inspect container", action.Request{Kind: action.ContainerInfo, Profile: "desktop-e2e", ID: "ctr-123"}, "InspectContainer", &pb.IdRequest{Profile: "desktop-e2e", Id: "ctr-123"}},
		{"container top", action.Request{Kind: action.ContainerTop, Profile: "desktop-e2e", ID: "ctr-123"}, "ContainerTop", &pb.IdRequest{Profile: "desktop-e2e", Id: "ctr-123"}},
		{"container stats", action.Request{Kind: action.ContainerStat, Profile: "desktop-e2e", ID: "ctr-123"}, "ContainerStats", &pb.IdRequest{Profile: "desktop-e2e", Id: "ctr-123"}},
		{"container changes", action.Request{Kind: action.ContainerDiff, Profile: "desktop-e2e", ID: "ctr-123"}, "ContainerChanges", &pb.IdRequest{Profile: "desktop-e2e", Id: "ctr-123"}},
		{"prune containers", action.Request{Kind: action.ContainerPrune, Profile: "desktop-e2e", All: true}, "PruneContainers", &pb.DockerScope{Profile: "desktop-e2e", All: true}},
		{"remove image", action.Request{Kind: action.ImageRemove, Profile: "desktop-e2e", ID: "sha256:abc"}, "RemoveImage", &pb.IdRequest{Profile: "desktop-e2e", Id: "sha256:abc"}},
		{"inspect image", action.Request{Kind: action.ImageInspect, Profile: "desktop-e2e", Name: "nginx:latest"}, "InspectImage", &pb.NameRequest{Profile: "desktop-e2e", Name: "nginx:latest"}},
		{"image history", action.Request{Kind: action.ImageHistory, Profile: "desktop-e2e", Name: "nginx:latest"}, "ImageHistory", &pb.NameRequest{Profile: "desktop-e2e", Name: "nginx:latest"}},
		{"tag image", action.Request{Kind: action.ImageTag, Profile: "desktop-e2e", WSL2: true, Name: "nginx:latest", Repository: "registry/app", Tag: "v2"}, "TagImage", &pb.TagRequest{Profile: "desktop-e2e", Wsl2: true, Name: "nginx:latest", Repo: "registry/app", Tag: "v2"}},
		{"search images", action.Request{Kind: action.ImageSearch, Profile: "desktop-e2e", Host: "user@host", Term: "alpine"}, "SearchImages", &pb.SearchRequest{Profile: "desktop-e2e", Host: "user@host", Term: "alpine"}},
		{"prune images", action.Request{Kind: action.ImagePrune, Profile: "desktop-e2e", All: true}, "PruneImages", &pb.DockerScope{Profile: "desktop-e2e", All: true}},
		{"create volume", action.Request{Kind: action.VolumeCreate, Profile: "desktop-e2e", Name: "data"}, "CreateVolume", &pb.NameRequest{Profile: "desktop-e2e", Name: "data"}},
		{"remove volume", action.Request{Kind: action.VolumeRemove, Profile: "desktop-e2e", Name: "data"}, "RemoveVolume", &pb.NameRequest{Profile: "desktop-e2e", Name: "data"}},
		{"inspect volume", action.Request{Kind: action.VolumeInspect, Profile: "desktop-e2e", Name: "data"}, "InspectVolume", &pb.NameRequest{Profile: "desktop-e2e", Name: "data"}},
		{"prune volumes", action.Request{Kind: action.VolumePrune, Profile: "desktop-e2e", All: true}, "PruneVolumes", &pb.DockerScope{Profile: "desktop-e2e", All: true}},
		{"create network", action.Request{Kind: action.NetworkCreate, Profile: "desktop-e2e", Name: "frontend"}, "CreateNetwork", &pb.NameRequest{Profile: "desktop-e2e", Name: "frontend"}},
		{"remove network", action.Request{Kind: action.NetworkRemove, Profile: "desktop-e2e", ID: "net-1"}, "RemoveNetwork", &pb.IdRequest{Profile: "desktop-e2e", Id: "net-1"}},
		{"inspect network", action.Request{Kind: action.NetworkInspect, Profile: "desktop-e2e", ID: "net-1"}, "InspectNetwork", &pb.IdRequest{Profile: "desktop-e2e", Id: "net-1"}},
		{"network connect", action.Request{Kind: action.NetworkConnect, Profile: "desktop-e2e", WSL2: true, ID: "net-1", ContainerID: "ctr-123"}, "ConnectNetwork", &pb.NetworkContainerRequest{Profile: "desktop-e2e", Wsl2: true, NetworkId: "net-1", ContainerId: "ctr-123"}},
		{"network disconnect", action.Request{Kind: action.NetworkDisconnect, Profile: "desktop-e2e", Host: "user@host", ID: "net-1", ContainerID: "ctr-123"}, "DisconnectNetwork", &pb.NetworkContainerRequest{Profile: "desktop-e2e", Host: "user@host", NetworkId: "net-1", ContainerId: "ctr-123"}},
		{"prune networks", action.Request{Kind: action.NetworkPrune, Profile: "desktop-e2e", All: true}, "PruneNetworks", &pb.DockerScope{Profile: "desktop-e2e", All: true}},
		{"kube start", action.Request{Kind: action.KubeStart, Profile: "desktop-e2e"}, "KubernetesStart", &pb.ProfileRequest{Profile: "desktop-e2e"}},
		{"kube stop", action.Request{Kind: action.KubeStop, Profile: "desktop-e2e"}, "KubernetesStop", &pb.ProfileRequest{Profile: "desktop-e2e"}},
		{"kube reset", action.Request{Kind: action.KubeReset, Profile: "desktop-e2e"}, "KubernetesReset", &pb.ProfileRequest{Profile: "desktop-e2e"}},
		{"create profile", action.Request{Kind: action.ProfileCreate, Name: "new", Config: config}, "CreateProfile", &pb.CreateProfileRequest{Name: "new", Config: config}},
		{"delete profile", action.Request{Kind: action.ProfileDelete, Name: "old", Data: true, Force: true}, "DeleteProfile", &pb.DeleteProfileRequest{Name: "old", Data: true, Force: true}},
		{"clone profile", action.Request{Kind: action.ProfileClone, Source: "default", Target: "copy"}, "CloneProfile", &pb.CloneProfileRequest{Source: "default", Destination: "copy"}},
		{"config", action.Request{Kind: action.ConfigSet, Profile: "desktop-e2e", Config: config}, "SetConfig", &pb.SetConfigRequest{Profile: "desktop-e2e", Config: config}},
		{"template", action.Request{Kind: action.TemplateSet, Config: config}, "SetTemplate", config},
		{"runtime", action.Request{Kind: action.RuntimeSwitch, Profile: "desktop-e2e", Runtime: "incus"}, "SwitchRuntime", &pb.SwitchRuntimeRequest{Profile: "desktop-e2e", Runtime: "incus"}},
		{"runtime update", action.Request{Kind: action.RuntimeUpdate, Profile: "desktop-e2e"}, "UpdateRuntime", &pb.ProfileRequest{Profile: "desktop-e2e"}},
		{"model serve", action.Request{Kind: action.ModelServe, Profile: "desktop-e2e", Model: "llama", Runner: "docker", Port: 8080}, "ModelServe", &pb.ModelServeRequest{Profile: "desktop-e2e", Model: "llama", Runner: "docker", Port: 8080}},
		{"model stop", action.Request{Kind: action.ModelStop, Profile: "desktop-e2e"}, "ModelStop", &pb.ProfileRequest{Profile: "desktop-e2e"}},
		{"kill", action.Request{Kind: action.ProcessKill, Profile: "desktop-e2e", PID: 4242, Signal: 9}, "KillProcess", &pb.KillProcessRequest{Profile: "desktop-e2e", Pid: 4242, Signal: 9}},
		{"kubectl", action.Request{Kind: action.KubeExec, Profile: "desktop-e2e", Command: "get pods -A"}, "KubernetesExec", &pb.KubeExecRequest{Profile: "desktop-e2e", Command: "get pods -A"}},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			result, err := client.RunAction(context.Background(), test.request)
			if err != nil {
				t.Fatal(err)
			}
			if test.request.Kind == action.KubeExec && result.Text != "pod-a" {
				t.Fatalf("kubectl output = %q", result.Text)
			}
			recorder.mu.Lock()
			defer recorder.mu.Unlock()
			if recorder.method != test.method {
				t.Fatalf("method = %q, want %q", recorder.method, test.method)
			}
			if !proto.Equal(recorder.request, test.want) {
				t.Fatalf("request = %s, want %s", recorder.request, test.want)
			}
		})
	}
}

func TestRunActionDoesNotTurnDaemonFailureIntoSuccess(t *testing.T) {
	client, recorder := newBufClient(t)
	recorder.mu.Lock()
	recorder.failNext = true
	recorder.mu.Unlock()
	_, err := client.RunAction(context.Background(), action.Request{Kind: action.VMStop, Profile: "desktop-e2e"})
	if err == nil || !strings.Contains(err.Error(), "daemon refused action") {
		t.Fatalf("expected application error, got %v", err)
	}
}

func TestOpenProgressUsesProfileAndStreamsRealEvent(t *testing.T) {
	client, recorder := newBufClient(t)
	cx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	stream, err := client.OpenProgress(cx, action.Request{Kind: action.VMStart, Profile: "desktop-e2e", Config: &pb.ColimaConfig{Cpu: 4}})
	if err != nil {
		t.Fatal(err)
	}
	event, err := stream.Recv()
	if err != nil {
		t.Fatal(err)
	}
	if !event.GetDone() || event.GetMessage() != "started" {
		t.Fatalf("unexpected progress event: %v", event)
	}
	recorder.mu.Lock()
	defer recorder.mu.Unlock()
	want := &pb.StartRequest{Profile: "desktop-e2e", Config: &pb.ColimaConfig{Cpu: 4}}
	if recorder.method != "Start" || !proto.Equal(recorder.request, want) {
		t.Fatalf("start request = %v, want %v", recorder.request, want)
	}
}

func TestStartWithoutOverrideLoadsSelectedProfileConfig(t *testing.T) {
	client, recorder := newBufClient(t)
	cx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	stream, err := client.OpenProgress(cx, action.Request{Kind: action.VMStart, Profile: "desktop-e2e"})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := stream.Recv(); err != nil {
		t.Fatal(err)
	}
	recorder.mu.Lock()
	defer recorder.mu.Unlock()
	want := &pb.StartRequest{Profile: "desktop-e2e", Config: &pb.ColimaConfig{Cpu: 7, Memory: 12, Runtime: "docker"}}
	if recorder.method != "Start" || !proto.Equal(recorder.request, want) {
		t.Fatalf("start request = %v, want %v", recorder.request, want)
	}
}

func TestEveryProgressActionUsesExactRPCPayload(t *testing.T) {
	client, recorder := newBufClient(t)
	tests := []struct {
		name    string
		request action.Request
		method  string
		want    proto.Message
	}{
		{"restart", action.Request{Kind: action.VMRestart, Profile: "desktop-e2e"}, "Restart", &pb.RestartRequest{Profile: "desktop-e2e"}},
		{"pull", action.Request{Kind: action.ImagePull, Profile: "desktop-e2e", Name: "alpine:latest"}, "PullImage", &pb.NameRequest{Profile: "desktop-e2e", Name: "alpine:latest"}},
		{"push", action.Request{Kind: action.ImagePush, Profile: "desktop-e2e", Name: "registry/app:v1"}, "PushImage", &pb.NameRequest{Profile: "desktop-e2e", Name: "registry/app:v1"}},
		{"model setup", action.Request{Kind: action.ModelSetup, Profile: "desktop-e2e", Runner: "ramalama"}, "ModelSetup", &pb.ModelRequest{Profile: "desktop-e2e", Runner: "ramalama"}},
		{"model run", action.Request{Kind: action.ModelRun, Profile: "desktop-e2e", Model: "llama", Runner: "docker", Prompt: "hello"}, "ModelRun", &pb.ModelRunRequest{Profile: "desktop-e2e", Model: "llama", Runner: "docker", Prompt: "hello"}},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			cx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
			defer cancel()
			stream, err := client.OpenProgress(cx, test.request)
			if err != nil {
				t.Fatal(err)
			}
			event, err := stream.Recv()
			if err != nil || !event.GetDone() {
				t.Fatalf("event=%v err=%v", event, err)
			}
			recorder.mu.Lock()
			defer recorder.mu.Unlock()
			if recorder.method != test.method || !proto.Equal(recorder.request, test.want) {
				t.Fatalf("method=%q request=%v, want method=%q request=%v", recorder.method, recorder.request, test.method, test.want)
			}
		})
	}
}

func TestNormalizeEndpoint(t *testing.T) {
	tests := map[string]string{
		"/tmp/colima-desktop.sock":        "unix:///tmp/colima-desktop.sock",
		"unix:/tmp/colima-desktop.sock":   "unix:///tmp/colima-desktop.sock",
		"unix:///tmp/colima-desktop.sock": "unix:///tmp/colima-desktop.sock",
		"127.0.0.1:50051":                 "127.0.0.1:50051",
		"tcp:127.0.0.1:50051":             "127.0.0.1:50051",
		"tcp://127.0.0.1:50051":           "127.0.0.1:50051",
	}
	for input, want := range tests {
		got, err := normalizeEndpoint(input)
		if err != nil {
			t.Errorf("normalizeEndpoint(%q): %v", input, err)
		} else if got != want {
			t.Errorf("normalizeEndpoint(%q) = %q, want %q", input, got, want)
		}
	}
	if _, err := normalizeEndpoint(" "); err == nil {
		t.Fatal("empty endpoint should be rejected")
	}
}

// TestDockerActionsForwardDockerTargetScope proves every container/image/volume/
// network action forwards the complete active docker target (profile + host +
// wsl2 per v1.1) to its DockerService RPC — not just the profile. This guards
// the idRequest()/nameRequest() helpers, ContainerAction, CreateContainer, and
// the four DockerScope prune calls, which previously dropped host/wsl2 while the
// inline Rename/Tag/Search/Connect/Disconnect builders threaded them.
func TestDockerActionsForwardDockerTargetScope(t *testing.T) {
	client, recorder := newBufClient(t)
	const (
		profile = "desktop-e2e"
		host    = "user@remote"
	)
	tests := []struct {
		name    string
		request action.Request
		method  string
		want    proto.Message
	}{
		// idRequest() helper — containers/images/networks
		{"container logs", action.Request{Kind: action.ContainerLogs, Profile: profile, Host: host, WSL2: true, ID: "ctr-1"}, "ContainerLogs", &pb.IdRequest{Profile: profile, Host: host, Wsl2: true, Id: "ctr-1"}},
		{"inspect container", action.Request{Kind: action.ContainerInfo, Profile: profile, Host: host, WSL2: true, ID: "ctr-1"}, "InspectContainer", &pb.IdRequest{Profile: profile, Host: host, Wsl2: true, Id: "ctr-1"}},
		{"container top", action.Request{Kind: action.ContainerTop, Profile: profile, Host: host, WSL2: true, ID: "ctr-1"}, "ContainerTop", &pb.IdRequest{Profile: profile, Host: host, Wsl2: true, Id: "ctr-1"}},
		{"container stats", action.Request{Kind: action.ContainerStat, Profile: profile, Host: host, WSL2: true, ID: "ctr-1"}, "ContainerStats", &pb.IdRequest{Profile: profile, Host: host, Wsl2: true, Id: "ctr-1"}},
		{"container changes", action.Request{Kind: action.ContainerDiff, Profile: profile, Host: host, WSL2: true, ID: "ctr-1"}, "ContainerChanges", &pb.IdRequest{Profile: profile, Host: host, Wsl2: true, Id: "ctr-1"}},
		{"remove image", action.Request{Kind: action.ImageRemove, Profile: profile, Host: host, WSL2: true, ID: "sha256:abc"}, "RemoveImage", &pb.IdRequest{Profile: profile, Host: host, Wsl2: true, Id: "sha256:abc"}},
		{"remove network", action.Request{Kind: action.NetworkRemove, Profile: profile, Host: host, WSL2: true, ID: "net-1"}, "RemoveNetwork", &pb.IdRequest{Profile: profile, Host: host, Wsl2: true, Id: "net-1"}},
		{"inspect network", action.Request{Kind: action.NetworkInspect, Profile: profile, Host: host, WSL2: true, ID: "net-1"}, "InspectNetwork", &pb.IdRequest{Profile: profile, Host: host, Wsl2: true, Id: "net-1"}},
		// nameRequest() helper — images/volumes/networks
		{"inspect image", action.Request{Kind: action.ImageInspect, Profile: profile, Host: host, WSL2: true, Name: "nginx:latest"}, "InspectImage", &pb.NameRequest{Profile: profile, Host: host, Wsl2: true, Name: "nginx:latest"}},
		{"image history", action.Request{Kind: action.ImageHistory, Profile: profile, Host: host, WSL2: true, Name: "nginx:latest"}, "ImageHistory", &pb.NameRequest{Profile: profile, Host: host, Wsl2: true, Name: "nginx:latest"}},
		{"create volume", action.Request{Kind: action.VolumeCreate, Profile: profile, Host: host, WSL2: true, Name: "data"}, "CreateVolume", &pb.NameRequest{Profile: profile, Host: host, Wsl2: true, Name: "data"}},
		{"remove volume", action.Request{Kind: action.VolumeRemove, Profile: profile, Host: host, WSL2: true, Name: "data"}, "RemoveVolume", &pb.NameRequest{Profile: profile, Host: host, Wsl2: true, Name: "data"}},
		{"inspect volume", action.Request{Kind: action.VolumeInspect, Profile: profile, Host: host, WSL2: true, Name: "data"}, "InspectVolume", &pb.NameRequest{Profile: profile, Host: host, Wsl2: true, Name: "data"}},
		{"create network", action.Request{Kind: action.NetworkCreate, Profile: profile, Host: host, WSL2: true, Name: "frontend"}, "CreateNetwork", &pb.NameRequest{Profile: profile, Host: host, Wsl2: true, Name: "frontend"}},
		// dedicated request builders — ContainerAction / CreateContainer
		{"container action", action.Request{Kind: action.ContainerDo, Profile: profile, Host: host, WSL2: true, ID: "ctr-1", Action: "stop"}, "ContainerAction", &pb.ContainerActionRequest{Profile: profile, Host: host, Wsl2: true, Id: "ctr-1", Action: "stop"}},
		{"create container", action.Request{Kind: action.ContainerNew, Profile: profile, Host: host, WSL2: true, Name: "web", Target: "nginx:latest"}, "CreateContainer", &pb.CreateContainerRequest{Profile: profile, Host: host, Wsl2: true, Name: "web", Image: "nginx:latest"}},
		// DockerScope prune builders — all four resource groups
		{"prune containers", action.Request{Kind: action.ContainerPrune, Profile: profile, Host: host, WSL2: true, All: true}, "PruneContainers", &pb.DockerScope{Profile: profile, Host: host, Wsl2: true, All: true}},
		{"prune images", action.Request{Kind: action.ImagePrune, Profile: profile, Host: host, WSL2: true, All: true}, "PruneImages", &pb.DockerScope{Profile: profile, Host: host, Wsl2: true, All: true}},
		{"prune volumes", action.Request{Kind: action.VolumePrune, Profile: profile, Host: host, WSL2: true, All: true}, "PruneVolumes", &pb.DockerScope{Profile: profile, Host: host, Wsl2: true, All: true}},
		{"prune networks", action.Request{Kind: action.NetworkPrune, Profile: profile, Host: host, WSL2: true, All: true}, "PruneNetworks", &pb.DockerScope{Profile: profile, Host: host, Wsl2: true, All: true}},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if _, err := client.RunAction(context.Background(), test.request); err != nil {
				t.Fatal(err)
			}
			recorder.mu.Lock()
			defer recorder.mu.Unlock()
			if recorder.method != test.method {
				t.Fatalf("method = %q, want %q", recorder.method, test.method)
			}
			if !proto.Equal(recorder.request, test.want) {
				t.Fatalf("request = %s, want %s", recorder.request, test.want)
			}
		})
	}
}

// TestStreamedImageActionsForwardDockerTargetScope proves the streamed pull/push
// actions (via nameRequest) also carry the complete active docker target, so a
// remote-ssh/wsl2 provider scope is not silently lost on image transfer streams.
func TestStreamedImageActionsForwardDockerTargetScope(t *testing.T) {
	client, recorder := newBufClient(t)
	const (
		profile = "desktop-e2e"
		host    = "user@remote"
	)
	tests := []struct {
		name    string
		request action.Request
		method  string
		want    proto.Message
	}{
		{"pull", action.Request{Kind: action.ImagePull, Profile: profile, Host: host, WSL2: true, Name: "alpine:latest"}, "PullImage", &pb.NameRequest{Profile: profile, Host: host, Wsl2: true, Name: "alpine:latest"}},
		{"push", action.Request{Kind: action.ImagePush, Profile: profile, Host: host, WSL2: true, Name: "registry/app:v1"}, "PushImage", &pb.NameRequest{Profile: profile, Host: host, Wsl2: true, Name: "registry/app:v1"}},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			cx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
			defer cancel()
			stream, err := client.OpenProgress(cx, test.request)
			if err != nil {
				t.Fatal(err)
			}
			if _, err := stream.Recv(); err != nil {
				t.Fatal(err)
			}
			recorder.mu.Lock()
			defer recorder.mu.Unlock()
			if recorder.method != test.method || !proto.Equal(recorder.request, test.want) {
				t.Fatalf("method=%q request=%v, want method=%q request=%v", recorder.method, recorder.request, test.method, test.want)
			}
		})
	}
}
