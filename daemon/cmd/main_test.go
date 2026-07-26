package main

import (
	"context"
	"errors"
	"io"
	"net"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"testing"
	"time"

	pb "github.com/colima-desktop/daemon/proto"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/grpc/test/bufconn"
)

func TestParseOptionsDefaultsAndCompatibility(t *testing.T) {
	tests := []struct {
		name string
		args []string
		goos string
		want []string
	}{
		{name: "unix default", goos: "linux", want: []string{"unix:" + defaultSocket}},
		{name: "windows default", goos: "windows", want: []string{"tcp:" + defaultWindowsTCP}},
		{name: "legacy socket", args: []string{"--socket", "/tmp/legacy.sock"}, goos: "linux", want: []string{"unix:/tmp/legacy.sock"}},
		{name: "repeatable listen", args: []string{"--listen", "unix:/tmp/a.sock", "--listen", "tcp:127.0.0.1:0"}, goos: "linux", want: []string{"unix:/tmp/a.sock", "tcp:127.0.0.1:0"}},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			got, err := parseOptions(test.args, test.goos, func(string) string { return "" })
			if err != nil {
				t.Fatalf("parse options: %v", err)
			}
			if strings.Join(got.listen, "|") != strings.Join(test.want, "|") {
				t.Fatalf("listeners = %#v, want %#v", got.listen, test.want)
			}
		})
	}
}

func TestParseOptionsRejectsConflictingAndPositionalArguments(t *testing.T) {
	for _, args := range [][]string{
		{"--socket", "/tmp/a.sock", "--listen", "unix:/tmp/b.sock"},
		{"unexpected"},
	} {
		if _, err := parseOptions(args, "linux", func(string) string { return "" }); err == nil {
			t.Fatalf("parseOptions(%q) succeeded", args)
		}
	}
}

func TestParseOptionsReadsListenFromEnvWhenNoFlag(t *testing.T) {
	env := func(key string) string {
		if key == listenEnvVar {
			return "unix:/tmp/env-a.sock, tcp:127.0.0.1:0"
		}
		return ""
	}
	// With no listener flag, the env var configures both listeners.
	got, err := parseOptions(nil, "linux", env)
	if err != nil {
		t.Fatalf("parse options: %v", err)
	}
	if want := []string{"unix:/tmp/env-a.sock", "tcp:127.0.0.1:0"}; strings.Join(got.listen, "|") != strings.Join(want, "|") {
		t.Fatalf("env listeners = %#v, want %#v", got.listen, want)
	}
	// An explicit flag wins over the env var.
	got, err = parseOptions([]string{"--listen", "unix:/tmp/flag.sock"}, "linux", env)
	if err != nil {
		t.Fatalf("parse options: %v", err)
	}
	if strings.Join(got.listen, "|") != "unix:/tmp/flag.sock" {
		t.Fatalf("flag did not override env: %#v", got.listen)
	}
	// An empty env var falls back to the platform default.
	got, err = parseOptions(nil, "windows", func(string) string { return "" })
	if err != nil {
		t.Fatalf("parse options: %v", err)
	}
	if strings.Join(got.listen, "|") != "tcp:"+defaultWindowsTCP {
		t.Fatalf("empty env did not fall back to default: %#v", got.listen)
	}
}

func TestParseListenSpecAllowsOnlyLoopbackTCP(t *testing.T) {
	valid := []string{
		"unix:/tmp/daemon.sock",
		"tcp:127.0.0.1:50051",
		"tcp:[::1]:50051",
	}
	for _, raw := range valid {
		if _, err := parseListenSpec(raw); err != nil {
			t.Errorf("parseListenSpec(%q): %v", raw, err)
		}
	}

	invalid := []string{
		"tcp:0.0.0.0:50051",
		"tcp:[::]:50051",
		"tcp:192.0.2.1:50051",
		"tcp:example.test:50051",
		"tcp:localhost:50051",
		"tcp:127.0.0.1:70000",
		"udp:127.0.0.1:50051",
		"unix:",
		"missing-prefix",
	}
	for _, raw := range invalid {
		if _, err := parseListenSpec(raw); err == nil {
			t.Errorf("parseListenSpec(%q) succeeded", raw)
		}
	}
}

func shortSocketPath(t *testing.T) string {
	t.Helper()
	dir, err := os.MkdirTemp("/tmp", "colima-listener-")
	if err != nil {
		t.Fatalf("create temp dir: %v", err)
	}
	t.Cleanup(func() { _ = os.RemoveAll(dir) })
	return filepath.Join(dir, "daemon.sock")
}

func TestListenUnixSecuresAndCleansSocket(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("Unix sockets are not available on native Windows")
	}
	path := shortSocketPath(t)
	listener, err := listen("unix:" + path)
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	info, err := os.Stat(path)
	if err != nil {
		t.Fatalf("stat socket: %v", err)
	}
	if got := info.Mode().Perm(); got != 0600 {
		t.Errorf("socket permissions = %o, want 600", got)
	}
	if err := listener.Close(); err != nil {
		t.Fatalf("close: %v", err)
	}
	if _, err := os.Lstat(path); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("socket remains after close: %v", err)
	}
}

func TestListenUnixRefusesRegularFile(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("Unix sockets are not available on native Windows")
	}
	path := shortSocketPath(t)
	if err := os.WriteFile(path, []byte("keep"), 0600); err != nil {
		t.Fatalf("write fixture: %v", err)
	}
	if _, err := listen("unix:" + path); err == nil || !strings.Contains(err.Error(), "non-socket") {
		t.Fatalf("listen error = %v", err)
	}
	data, err := os.ReadFile(path)
	if err != nil || string(data) != "keep" {
		t.Fatalf("regular file was changed: data=%q err=%v", data, err)
	}
}

func TestListenUnixRejectsActiveAndReplacesStaleSocket(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("Unix sockets are not available on native Windows")
	}

	t.Run("active", func(t *testing.T) {
		path := shortSocketPath(t)
		active, err := net.Listen("unix", path)
		if err != nil {
			t.Fatalf("listen fixture: %v", err)
		}
		defer active.Close()
		if _, err := listen("unix:" + path); err == nil || !strings.Contains(err.Error(), "already active") {
			t.Fatalf("listen error = %v", err)
		}
	})

	t.Run("stale", func(t *testing.T) {
		path := shortSocketPath(t)
		stale, err := net.Listen("unix", path)
		if err != nil {
			t.Fatalf("listen fixture: %v", err)
		}
		stale.(*net.UnixListener).SetUnlinkOnClose(false)
		if err := stale.Close(); err != nil {
			t.Fatalf("close fixture: %v", err)
		}
		listener, err := listen("unix:" + path)
		if err != nil {
			t.Fatalf("replace stale socket: %v", err)
		}
		_ = listener.Close()
	})
}

func TestListenUnixRefusesDifferentSocketType(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("Unix sockets are not available on native Windows")
	}
	path := shortSocketPath(t)
	packet, err := net.ListenPacket("unixgram", path)
	if err != nil {
		t.Fatalf("listen packet fixture: %v", err)
	}
	defer packet.Close()

	if _, err := listen("unix:" + path); err == nil || !strings.Contains(err.Error(), "refusing to remove") {
		t.Fatalf("listen error = %v", err)
	}
	if _, err := os.Lstat(path); err != nil {
		t.Fatalf("different socket type was removed: %v", err)
	}
}

func TestListenUnixDoesNotRemoveReplacementPath(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("Unix sockets are not available on native Windows")
	}
	path := shortSocketPath(t)
	listener, err := listen("unix:" + path)
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	if err := os.Remove(path); err != nil {
		t.Fatalf("remove socket path: %v", err)
	}
	if err := os.WriteFile(path, []byte("replacement"), 0600); err != nil {
		t.Fatalf("write replacement: %v", err)
	}
	_ = listener.Close()
	data, err := os.ReadFile(path)
	if err != nil || string(data) != "replacement" {
		t.Fatalf("replacement path was removed: data=%q err=%v", data, err)
	}
}

func TestListenTCPUsesLoopbackAndDoesNotRemoveAddress(t *testing.T) {
	listener, err := listen("tcp:127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	address := listener.Addr().(*net.TCPAddr)
	if !address.IP.IsLoopback() {
		t.Fatalf("bound address = %v, want loopback", address)
	}
	if err := listener.Close(); err != nil {
		t.Fatalf("close: %v", err)
	}
}

func TestRunGracefulShutdownRemovesUnixSocket(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("Unix sockets are not available on native Windows")
	}
	path := shortSocketPath(t)
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- run(ctx, []string{"unix:" + path}) }()

	deadline := time.Now().Add(2 * time.Second)
	for {
		if _, err := os.Stat(path); err == nil {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("daemon did not create Unix socket")
		}
		time.Sleep(10 * time.Millisecond)
	}
	cancel()
	select {
	case err := <-done:
		if err != nil {
			t.Fatalf("run: %v", err)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("daemon did not shut down")
	}
	if _, err := os.Lstat(path); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("socket remains after shutdown: %v", err)
	}
}

func TestRunSupportsMultipleListeners(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("Unix sockets are not available on native Windows")
	}
	path := shortSocketPath(t)
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- run(ctx, []string{"unix:" + path, "tcp:127.0.0.1:0"}) }()

	deadline := time.Now().Add(2 * time.Second)
	for {
		if _, err := os.Stat(path); err == nil {
			break
		}
		select {
		case err := <-done:
			t.Fatalf("run stopped before cancellation: %v", err)
		default:
		}
		if time.Now().After(deadline) {
			t.Fatal("daemon did not create Unix socket")
		}
		time.Sleep(10 * time.Millisecond)
	}
	cancel()
	select {
	case err := <-done:
		if err != nil {
			t.Fatalf("run: %v", err)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("daemon did not stop both listeners")
	}
}

func TestRunCleansEarlierListenersWhenLaterBindFails(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("Unix sockets are not available on native Windows")
	}
	path := shortSocketPath(t)
	err := run(context.Background(), []string{"unix:" + path, "tcp:0.0.0.0:50051"})
	if err == nil || !strings.Contains(err.Error(), "not a literal loopback") {
		t.Fatalf("run error = %v", err)
	}
	if _, err := os.Lstat(path); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("earlier Unix listener was not cleaned: %v", err)
	}
}

func TestRunGracefulShutdownTCP(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- run(ctx, []string{"tcp:127.0.0.1:0"}) }()
	time.Sleep(25 * time.Millisecond)
	cancel()
	select {
	case err := <-done:
		if err != nil {
			t.Fatalf("run: %v", err)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("TCP daemon did not shut down")
	}
}

type failingListener struct {
	closed chan struct{}
	once   sync.Once
}

func (listener *failingListener) Accept() (net.Conn, error) {
	return nil, errors.New("accept failed")
}

func (listener *failingListener) Close() error {
	listener.once.Do(func() { close(listener.closed) })
	return nil
}

func (listener *failingListener) Addr() net.Addr {
	return &net.TCPAddr{IP: net.IPv4(127, 0, 0, 1)}
}

func TestServePropagatesListenerError(t *testing.T) {
	failed := &failingListener{closed: make(chan struct{})}
	listener := &managedListener{
		Listener: failed,
		spec:     listenSpec{network: "tcp", address: "127.0.0.1:0"},
	}
	grpcServer := grpc.NewServer()
	err := serve(context.Background(), grpcServer, []*managedListener{listener}, time.Second)
	if err == nil || !strings.Contains(err.Error(), "accept failed") {
		t.Fatalf("serve error = %v", err)
	}
}

func TestServeRejectsNoListeners(t *testing.T) {
	err := serve(context.Background(), grpc.NewServer(), nil, time.Second)
	if err == nil || !strings.Contains(err.Error(), "at least one listener") {
		t.Fatalf("serve error = %v", err)
	}
}

// TestServeDrainsInFlightStreamOnGracefulShutdown proves that graceful shutdown
// lets an in-flight server stream finish (drain) instead of cutting it off. A
// generic bidi stream is registered without generated code: it sends one
// message, blocks until released, then sends a final message. Shutdown is
// triggered while the handler is still blocked; the client must nonetheless
// receive the final message and a clean EOF, and serve() must return nil.
func TestServeDrainsInFlightStreamOnGracefulShutdown(t *testing.T) {
	streamStarted := make(chan struct{})
	releaseStream := make(chan struct{})

	desc := grpc.ServiceDesc{
		ServiceName: "drain.test.Service",
		HandlerType: (*any)(nil),
		Streams: []grpc.StreamDesc{{
			StreamName:    "Stream",
			ServerStreams: true,
			ClientStreams: true,
			Handler: func(_ any, stream grpc.ServerStream) error {
				close(streamStarted)
				if err := stream.SendMsg(&pb.Empty{}); err != nil {
					return err
				}
				<-releaseStream
				return stream.SendMsg(&pb.Empty{})
			},
		}},
	}

	grpcServer := grpc.NewServer()
	grpcServer.RegisterService(&desc, nil)

	lis := bufconn.Listen(1024 * 1024)
	managed := &managedListener{Listener: lis, spec: listenSpec{network: "tcp", address: "bufnet"}}

	serveDone := make(chan error, 1)
	ctx, cancel := context.WithCancel(context.Background())
	go func() { serveDone <- serve(ctx, grpcServer, []*managedListener{managed}, 5*time.Second) }()

	conn, err := grpc.NewClient(
		"passthrough:///bufnet",
		grpc.WithContextDialer(func(ctx context.Context, _ string) (net.Conn, error) { return lis.DialContext(ctx) }),
		grpc.WithTransportCredentials(insecure.NewCredentials()),
	)
	if err != nil {
		t.Fatalf("dial: %v", err)
	}
	defer conn.Close()

	streamCtx, streamCancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer streamCancel()
	clientDesc := &grpc.StreamDesc{StreamName: "Stream", ServerStreams: true, ClientStreams: true}
	stream, err := conn.NewStream(streamCtx, clientDesc, "/drain.test.Service/Stream")
	if err != nil {
		t.Fatalf("new stream: %v", err)
	}

	// Wait until the handler is running so the stream is provably in-flight.
	select {
	case <-streamStarted:
	case <-time.After(2 * time.Second):
		t.Fatal("stream handler did not start")
	}
	if err := stream.RecvMsg(&pb.Empty{}); err != nil {
		t.Fatalf("receive first message: %v", err)
	}

	// Trigger graceful shutdown while the handler is still blocked, then give
	// GracefulStop time to begin waiting for the in-flight RPC before releasing.
	cancel()
	time.Sleep(50 * time.Millisecond)
	close(releaseStream)

	// The drained stream must still deliver its final message, then a clean EOF.
	if err := stream.RecvMsg(&pb.Empty{}); err != nil {
		t.Fatalf("in-flight stream was not drained: %v", err)
	}
	if err := stream.RecvMsg(&pb.Empty{}); err != io.EOF {
		t.Fatalf("want EOF after drain, got %v", err)
	}

	select {
	case err := <-serveDone:
		if err != nil {
			t.Fatalf("serve returned error after graceful shutdown: %v", err)
		}
	case <-time.After(3 * time.Second):
		t.Fatal("serve did not return after graceful shutdown")
	}
}
