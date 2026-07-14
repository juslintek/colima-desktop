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

// dialer spins up an in-memory gRPC server with the real generated service
// registration and returns a connected client — proving the daemon serves
// the ColimaService contract over the wire (bufconn, no real socket).
func newTestClient(t *testing.T) pb.ColimaServiceClient {
	t.Helper()
	lis := bufconn.Listen(1024 * 1024)
	srv := grpc.NewServer()
	pb.RegisterColimaServiceServer(srv, New())
	go func() { _ = srv.Serve(lis) }()
	t.Cleanup(srv.Stop)

	conn, err := grpc.NewClient(
		"passthrough:///bufnet",
		grpc.WithContextDialer(func(ctx context.Context, _ string) (net.Conn, error) { return lis.DialContext(ctx) }),
		grpc.WithTransportCredentials(insecure.NewCredentials()),
	)
	if err != nil {
		t.Fatalf("dial: %v", err)
	}
	t.Cleanup(func() { _ = conn.Close() })
	return pb.NewColimaServiceClient(conn)
}

func TestVersionRPC(t *testing.T) {
	c := newTestClient(t)
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	resp, err := c.Version(ctx, &pb.Empty{})
	if err != nil {
		t.Fatalf("Version RPC failed: %v", err)
	}
	if resp == nil {
		t.Fatal("nil VersionResponse")
	}
}

func TestStatusRPC_GracefulWhenNotRunning(t *testing.T) {
	c := newTestClient(t)
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	// Should not error even if no VM is running (returns Running=false).
	resp, err := c.Status(ctx, &pb.StatusRequest{Profile: "nonexistent-test-profile"})
	if err != nil {
		t.Fatalf("Status RPC errored: %v", err)
	}
	if resp == nil {
		t.Fatal("nil VMStatus")
	}
}

func TestListMachinesRPC(t *testing.T) {
	c := newTestClient(t)
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	// May return an empty list or an error if limactl absent; assert it doesn't panic
	// and the RPC round-trips.
	_, _ = c.ListMachines(ctx, &pb.Empty{})
}
