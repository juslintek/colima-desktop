package server

import (
	"context"
	"errors"
	"io"
	"net"
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

func newDockerClient(t *testing.T, implementations ...pb.DockerServiceServer) pb.DockerServiceClient {
	t.Helper()
	lis := bufconn.Listen(1024 * 1024)
	srv := grpc.NewServer()
	implementation := pb.DockerServiceServer(NewDocker())
	if len(implementations) > 0 {
		implementation = implementations[0]
	}
	pb.RegisterDockerServiceServer(srv, implementation)
	go func() { _ = srv.Serve(lis) }()
	t.Cleanup(srv.Stop)
	conn, err := grpc.NewClient("passthrough:///bufnet",
		grpc.WithContextDialer(func(ctx context.Context, _ string) (net.Conn, error) { return lis.DialContext(ctx) }),
		grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		t.Fatalf("dial: %v", err)
	}
	t.Cleanup(func() { _ = conn.Close() })
	return pb.NewDockerServiceClient(conn)
}

// Round-trips ListContainers over the wire. If the local docker socket is
// unreachable the handler returns JsonResponse.Error (not a transport error) —
// either way the DockerService contract is proven to serve.
func TestDockerListContainersRPC(t *testing.T) {
	c := newDockerClient(t)
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	resp, err := c.ListContainers(ctx, &pb.DockerScope{Profile: "default", All: true})
	if err != nil {
		t.Fatalf("transport error: %v", err)
	}
	if resp == nil {
		t.Fatal("nil response")
	}
}

func TestDockerActionRoundTrip(t *testing.T) {
	c := newDockerClient(t)
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	// Unknown id → handler returns StatusResponse{Success:false}, not a transport error.
	resp, err := c.ContainerAction(ctx, &pb.ContainerActionRequest{Id: "nonexistent", Action: "start", Profile: "default"})
	if err != nil {
		t.Fatalf("transport error: %v", err)
	}
	if resp == nil {
		t.Fatal("nil response")
	}
}

func TestPreviouslyUnscopedDockerRPCsForwardProviderSelection(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("WSL2 is a valid provider on Windows; this assertion uses the non-Windows provider error as its routing probe")
	}
	client := newDockerClient(t)
	tests := []struct {
		name   string
		invoke func(context.Context) (string, error)
	}{
		{
			name: "RenameContainer",
			invoke: func(ctx context.Context) (string, error) {
				response, err := client.RenameContainer(ctx, &pb.RenameRequest{Id: "container", NewName: "new", Profile: "dev", Wsl2: true})
				if err != nil {
					return "", err
				}
				return response.Error, nil
			},
		},
		{
			name: "TagImage",
			invoke: func(ctx context.Context) (string, error) {
				response, err := client.TagImage(ctx, &pb.TagRequest{Name: "image", Repo: "repo", Tag: "tag", Profile: "dev", Wsl2: true})
				if err != nil {
					return "", err
				}
				return response.Error, nil
			},
		},
		{
			name: "SearchImages",
			invoke: func(ctx context.Context) (string, error) {
				response, err := client.SearchImages(ctx, &pb.SearchRequest{Term: "image", Profile: "dev", Wsl2: true})
				if err != nil {
					return "", err
				}
				return response.Error, nil
			},
		},
		{
			name: "ConnectNetwork",
			invoke: func(ctx context.Context) (string, error) {
				response, err := client.ConnectNetwork(ctx, &pb.NetworkContainerRequest{NetworkId: "network", ContainerId: "container", Profile: "dev", Wsl2: true})
				if err != nil {
					return "", err
				}
				return response.Error, nil
			},
		},
		{
			name: "DisconnectNetwork",
			invoke: func(ctx context.Context) (string, error) {
				response, err := client.DisconnectNetwork(ctx, &pb.NetworkContainerRequest{NetworkId: "network", ContainerId: "container", Profile: "dev", Wsl2: true})
				if err != nil {
					return "", err
				}
				return response.Error, nil
			},
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			ctx, cancel := context.WithTimeout(context.Background(), time.Second)
			defer cancel()
			providerError, err := test.invoke(ctx)
			if err != nil {
				t.Fatalf("transport error: %v", err)
			}
			if !strings.Contains(providerError, "wsl2 backend") {
				t.Fatalf("provider error = %q, want WSL2 provider routing evidence", providerError)
			}
		})
	}
}

type fakeImageClient struct {
	pull  func(context.Context, string) (io.ReadCloser, error)
	push  func(context.Context, string) (io.ReadCloser, error)
	close func()
}

func (c *fakeImageClient) PullImage(ctx context.Context, name string) (io.ReadCloser, error) {
	if c.pull == nil {
		return nil, errors.New("unexpected pull")
	}
	return c.pull(ctx, name)
}

func (c *fakeImageClient) PushImage(ctx context.Context, name string) (io.ReadCloser, error) {
	if c.push == nil {
		return nil, errors.New("unexpected push")
	}
	return c.push(ctx, name)
}

func (c *fakeImageClient) CloseIdleConnections() {
	if c.close != nil {
		c.close()
	}
}

type progressReceiver interface {
	Recv() (*pb.ProgressEvent, error)
}

type imageRPC func(pb.DockerServiceClient, context.Context, *pb.NameRequest) (progressReceiver, error)

func imageRPCs() map[string]imageRPC {
	return map[string]imageRPC{
		"pull": func(client pb.DockerServiceClient, ctx context.Context, request *pb.NameRequest) (progressReceiver, error) {
			return client.PullImage(ctx, request)
		},
		"push": func(client pb.DockerServiceClient, ctx context.Context, request *pb.NameRequest) (progressReceiver, error) {
			return client.PushImage(ctx, request)
		},
	}
}

func receiveProgress(t *testing.T, receiver progressReceiver) []*pb.ProgressEvent {
	t.Helper()
	var events []*pb.ProgressEvent
	for {
		event, err := receiver.Recv()
		if err == io.EOF {
			return events
		}
		if err != nil {
			t.Fatalf("receive progress: %v", err)
		}
		events = append(events, event)
	}
}

func imageStreamClient(operation string, body string) *fakeImageClient {
	open := func(context.Context, string) (io.ReadCloser, error) {
		return io.NopCloser(strings.NewReader(body)), nil
	}
	client := &fakeImageClient{}
	if operation == "pull" {
		client.pull = open
	} else {
		client.push = open
	}
	return client
}

func TestImageRPCStreamsDockerProgress(t *testing.T) {
	const response = "" +
		`{"status":"Downloading","progressDetail":{"current":5,"total":10},"progress":"[====>     ]","id":"layer-1"}` + "\n" +
		`{"status":"Download complete","progressDetail":{},"id":"layer-1"}` + "\n"

	for operation, invoke := range imageRPCs() {
		t.Run(operation, func(t *testing.T) {
			server := NewDocker()
			server.imageClientFactory = func(docker.Target) (imageClient, error) {
				return imageStreamClient(operation, response), nil
			}
			client := newDockerClient(t, server)
			stream, err := invoke(client, context.Background(), &pb.NameRequest{Name: "alpine:latest", Profile: "test"})
			if err != nil {
				t.Fatalf("start stream: %v", err)
			}
			events := receiveProgress(t, stream)
			if len(events) != 4 {
				t.Fatalf("events = %d, want initial + 2 docker + terminal: %#v", len(events), events)
			}
			if events[1].Progress != 0.5 {
				t.Errorf("layer progress = %v, want 0.5", events[1].Progress)
			}
			if !strings.Contains(events[1].Message, "layer-1: Downloading") {
				t.Errorf("progress message = %q", events[1].Message)
			}
			terminal := events[len(events)-1]
			if !terminal.Done || terminal.Progress != 1 || terminal.Error != "" {
				t.Errorf("terminal event = %#v", terminal)
			}
		})
	}
}

func TestImageRPCForwardsEveryProviderScope(t *testing.T) {
	targets := []struct {
		name    string
		request *pb.NameRequest
		want    docker.Target
	}{
		{
			name:    "local-unix",
			request: &pb.NameRequest{Name: "alpine", Profile: "local-profile"},
			want:    docker.Target{Profile: "local-profile"},
		},
		{
			name:    "remote-ssh",
			request: &pb.NameRequest{Name: "alpine", Profile: "remote-profile", Host: "dev@example.test"},
			want:    docker.Target{Profile: "remote-profile", Host: "dev@example.test"},
		},
		{
			name:    "windows-wsl2",
			request: &pb.NameRequest{Name: "alpine", Profile: "wsl-profile", Wsl2: true},
			want:    docker.Target{Profile: "wsl-profile", WSL2: true},
		},
	}

	for operation, invoke := range imageRPCs() {
		for _, target := range targets {
			t.Run(operation+"/"+target.name, func(t *testing.T) {
				gotTarget := make(chan docker.Target, 1)
				server := NewDocker()
				server.imageClientFactory = func(actual docker.Target) (imageClient, error) {
					gotTarget <- actual
					return imageStreamClient(operation, `{"status":"ok"}`), nil
				}
				client := newDockerClient(t, server)
				stream, err := invoke(client, context.Background(), target.request)
				if err != nil {
					t.Fatalf("start stream: %v", err)
				}
				events := receiveProgress(t, stream)
				if len(events) == 0 || !events[len(events)-1].Done {
					t.Fatalf("missing terminal event: %#v", events)
				}
				if actual := <-gotTarget; actual != target.want {
					t.Errorf("target = %#v, want %#v", actual, target.want)
				}
			})
		}
	}
}

func TestImageRPCPropagatesProviderAndDockerErrors(t *testing.T) {
	tests := []struct {
		name      string
		operation string
		factory   imageClientFactory
		wantError string
	}{
		{
			name:      "provider creation",
			operation: "pull",
			factory: func(docker.Target) (imageClient, error) {
				return nil, errors.New("provider unavailable")
			},
			wantError: "provider unavailable",
		},
		{
			name:      "http stream open",
			operation: "push",
			factory: func(docker.Target) (imageClient, error) {
				return &fakeImageClient{push: func(context.Context, string) (io.ReadCloser, error) {
					return nil, errors.New("docker api 401: denied")
				}}, nil
			},
			wantError: "docker api 401: denied",
		},
		{
			name:      "docker progress payload",
			operation: "pull",
			factory: func(docker.Target) (imageClient, error) {
				return imageStreamClient("pull", `{"errorDetail":{"message":"manifest unknown"},"error":"manifest unknown"}`), nil
			},
			wantError: "manifest unknown",
		},
		{
			name:      "malformed progress payload",
			operation: "push",
			factory: func(docker.Target) (imageClient, error) {
				return imageStreamClient("push", `{not-json}`), nil
			},
			wantError: "decode docker image-push progress",
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			server := NewDocker()
			server.imageClientFactory = test.factory
			client := newDockerClient(t, server)
			stream, err := imageRPCs()[test.operation](client, context.Background(), &pb.NameRequest{Name: "image", Profile: "test"})
			if err != nil {
				t.Fatalf("start stream: %v", err)
			}
			events := receiveProgress(t, stream)
			if len(events) == 0 {
				t.Fatal("no error event received")
			}
			terminal := events[len(events)-1]
			if !terminal.Done || !strings.Contains(terminal.Error, test.wantError) {
				t.Fatalf("terminal event = %#v, want error containing %q", terminal, test.wantError)
			}
		})
	}
}

type contextReadCloser struct {
	ctx       context.Context
	closed    chan struct{}
	closeOnce sync.Once
}

func (r *contextReadCloser) Read([]byte) (int, error) {
	<-r.ctx.Done()
	return 0, r.ctx.Err()
}

func (r *contextReadCloser) Close() error {
	r.closeOnce.Do(func() { close(r.closed) })
	return nil
}

func TestImageRPCCancellationClosesBodyAndProviderConnections(t *testing.T) {
	for operation, invoke := range imageRPCs() {
		t.Run(operation, func(t *testing.T) {
			bodyClosed := make(chan struct{})
			providerClosed := make(chan struct{})
			var providerCloseOnce sync.Once
			open := func(ctx context.Context, _ string) (io.ReadCloser, error) {
				return &contextReadCloser{ctx: ctx, closed: bodyClosed}, nil
			}
			fake := &fakeImageClient{close: func() {
				providerCloseOnce.Do(func() { close(providerClosed) })
			}}
			if operation == "pull" {
				fake.pull = open
			} else {
				fake.push = open
			}
			server := NewDocker()
			server.imageClientFactory = func(docker.Target) (imageClient, error) { return fake, nil }
			client := newDockerClient(t, server)

			ctx, cancel := context.WithCancel(context.Background())
			stream, err := invoke(client, ctx, &pb.NameRequest{Name: "large-image", Profile: "test"})
			if err != nil {
				t.Fatalf("start stream: %v", err)
			}
			if _, err := stream.Recv(); err != nil {
				t.Fatalf("receive initial event: %v", err)
			}
			cancel()
			if _, err := stream.Recv(); status.Code(err) != codes.Canceled {
				t.Fatalf("receive after cancel = %v (%s), want Canceled", err, status.Code(err))
			}

			for name, closed := range map[string]<-chan struct{}{
				"response body":        bodyClosed,
				"provider connections": providerClosed,
			} {
				select {
				case <-closed:
				case <-time.After(time.Second):
					t.Errorf("%s were not closed after cancellation", name)
				}
			}
		})
	}
}
