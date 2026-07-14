package server

import (
	"context"
	"net"
	"testing"
	"time"

	pb "github.com/colima-desktop/daemon/proto"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/grpc/test/bufconn"
)

func newDockerClient(t *testing.T) pb.DockerServiceClient {
	t.Helper()
	lis := bufconn.Listen(1024 * 1024)
	srv := grpc.NewServer()
	pb.RegisterDockerServiceServer(srv, NewDocker())
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
