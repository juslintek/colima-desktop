package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"os/signal"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/colima-desktop/daemon/internal/server"
	"google.golang.org/grpc"
)

const (
	defaultSocket       = "/tmp/colima-desktop.sock"
	defaultWindowsTCP   = "127.0.0.1:50051"
	gracefulStopTimeout = 10 * time.Second
	// listenEnvVar configures the listeners when no --listen/--socket flag is
	// given. It holds a comma-separated list of specs, e.g.
	// "unix:/tmp/colima-desktop.sock,tcp:127.0.0.1:50051".
	listenEnvVar = "COLIMA_DAEMON_LISTEN"
)

type listenValues []string

func (values *listenValues) String() string { return strings.Join(*values, ",") }

func (values *listenValues) Set(value string) error {
	*values = append(*values, value)
	return nil
}

type options struct {
	listen []string
}

func defaultListen(goos string) []string {
	if goos == "windows" {
		return []string{"tcp:" + defaultWindowsTCP}
	}
	return []string{"unix:" + defaultSocket}
}

func parseOptions(args []string, goos string, getenv func(string) string) (options, error) {
	flags := flag.NewFlagSet("colima-daemon", flag.ContinueOnError)
	flags.SetOutput(io.Discard)
	var listeners listenValues
	var legacySocket string
	flags.Var(&listeners, "listen", "listener address (repeatable): unix:/path or tcp:127.0.0.1:port")
	flags.StringVar(&legacySocket, "socket", "", "deprecated Unix socket path (use --listen unix:/path)")
	if err := flags.Parse(args); err != nil {
		return options{}, err
	}
	if flags.NArg() != 0 {
		return options{}, fmt.Errorf("unexpected arguments: %s", strings.Join(flags.Args(), " "))
	}
	if legacySocket != "" {
		if len(listeners) != 0 {
			return options{}, fmt.Errorf("--socket cannot be combined with --listen")
		}
		listeners = append(listeners, "unix:"+legacySocket)
	}
	// Flags win. When no listener flag is given, fall back to the
	// COLIMA_DAEMON_LISTEN environment variable (comma-separated specs) so both
	// listeners stay configurable on hosts that prefer environment config, then
	// to the platform default when neither is set.
	if len(listeners) == 0 && getenv != nil {
		for _, part := range strings.Split(getenv(listenEnvVar), ",") {
			if part = strings.TrimSpace(part); part != "" {
				listeners = append(listeners, part)
			}
		}
	}
	if len(listeners) == 0 {
		listeners = defaultListen(goos)
	}
	return options{listen: append([]string(nil), listeners...)}, nil
}

type listenSpec struct {
	network string
	address string
}

func parseListenSpec(raw string) (listenSpec, error) {
	network, address, found := strings.Cut(raw, ":")
	if !found || address == "" {
		return listenSpec{}, fmt.Errorf("invalid listener %q: expected unix:/path or tcp:127.0.0.1:port", raw)
	}
	switch network {
	case "unix":
		return listenSpec{network: network, address: address}, nil
	case "tcp":
		host, portText, err := net.SplitHostPort(address)
		if err != nil {
			return listenSpec{}, fmt.Errorf("invalid TCP listener %q: %w", raw, err)
		}
		ip := net.ParseIP(host)
		if ip == nil || !ip.IsLoopback() {
			return listenSpec{}, fmt.Errorf("TCP listener %q is not a literal loopback address", raw)
		}
		port, err := strconv.Atoi(portText)
		if err != nil || port < 0 || port > 65535 {
			return listenSpec{}, fmt.Errorf("invalid TCP port in listener %q", raw)
		}
		return listenSpec{network: network, address: address}, nil
	default:
		return listenSpec{}, fmt.Errorf("unsupported listener network %q", network)
	}
}

type managedListener struct {
	net.Listener
	spec       listenSpec
	socketInfo os.FileInfo
	closeOnce  sync.Once
	closeErr   error
}

func listen(raw string) (*managedListener, error) {
	spec, err := parseListenSpec(raw)
	if err != nil {
		return nil, err
	}
	if spec.network == "unix" {
		if err := prepareUnixSocket(spec.address); err != nil {
			return nil, err
		}
	}
	listener, err := net.Listen(spec.network, spec.address)
	if err != nil {
		return nil, fmt.Errorf("listen on %s: %w", raw, err)
	}
	managed := &managedListener{Listener: listener, spec: spec}
	if spec.network == "unix" {
		if unixListener, ok := listener.(*net.UnixListener); ok {
			// Cleanup below verifies socket identity before unlinking. Disable the
			// standard library's unconditional unlink-on-close behavior so a path
			// replaced while the daemon runs is never removed accidentally.
			unixListener.SetUnlinkOnClose(false)
		}
		if err := os.Chmod(spec.address, 0600); err != nil {
			_ = listener.Close()
			_ = os.Remove(spec.address)
			return nil, fmt.Errorf("secure Unix listener %q: %w", spec.address, err)
		}
		managed.socketInfo, err = os.Lstat(spec.address)
		if err != nil {
			_ = listener.Close()
			return nil, fmt.Errorf("inspect Unix listener %q: %w", spec.address, err)
		}
	}
	return managed, nil
}

func prepareUnixSocket(path string) error {
	info, err := os.Lstat(path)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return fmt.Errorf("inspect Unix listener %q: %w", path, err)
	}
	if info.Mode()&os.ModeSocket == 0 {
		return fmt.Errorf("refusing to remove non-socket path %q", path)
	}
	conn, dialErr := net.DialTimeout("unix", path, 100*time.Millisecond)
	if dialErr == nil {
		_ = conn.Close()
		return fmt.Errorf("Unix listener %q is already active", path)
	}
	if errors.Is(dialErr, os.ErrNotExist) {
		// The listener disappeared after Lstat; there is nothing left to clean.
		return nil
	}
	if !errors.Is(dialErr, syscall.ECONNREFUSED) {
		return fmt.Errorf("refusing to remove Unix listener %q after probe failed: %w", path, dialErr)
	}
	if err := os.Remove(path); err != nil {
		return fmt.Errorf("remove stale Unix listener %q: %w", path, err)
	}
	return nil
}

func (listener *managedListener) Close() error {
	listener.closeOnce.Do(func() {
		listener.closeErr = listener.Listener.Close()
		if errors.Is(listener.closeErr, net.ErrClosed) {
			listener.closeErr = nil
		}
		if listener.spec.network != "unix" {
			return
		}
		current, err := os.Lstat(listener.spec.address)
		if errors.Is(err, os.ErrNotExist) {
			return
		}
		if err != nil {
			if listener.closeErr == nil {
				listener.closeErr = fmt.Errorf("inspect Unix listener during cleanup: %w", err)
			}
			return
		}
		if current.Mode()&os.ModeSocket != 0 && os.SameFile(listener.socketInfo, current) {
			if removeErr := os.Remove(listener.spec.address); listener.closeErr == nil {
				listener.closeErr = removeErr
			}
		}
	})
	return listener.closeErr
}

func serve(ctx context.Context, grpcServer *grpc.Server, listeners []*managedListener, gracePeriod time.Duration) error {
	if len(listeners) == 0 {
		return fmt.Errorf("at least one listener is required")
	}
	serveErrors := make(chan error, len(listeners))
	for _, listener := range listeners {
		listener := listener
		go func() {
			err := grpcServer.Serve(listener)
			if errors.Is(err, grpc.ErrServerStopped) {
				err = nil
			}
			serveErrors <- err
		}()
	}

	select {
	case <-ctx.Done():
		stopped := make(chan struct{})
		go func() {
			grpcServer.GracefulStop()
			close(stopped)
		}()
		timer := time.NewTimer(gracePeriod)
		defer timer.Stop()
		select {
		case <-stopped:
		case <-timer.C:
			grpcServer.Stop()
			<-stopped
		}
		return nil
	case err := <-serveErrors:
		grpcServer.Stop()
		if err == nil {
			return fmt.Errorf("gRPC listener stopped unexpectedly")
		}
		return fmt.Errorf("serve gRPC: %w", err)
	}
}

func run(ctx context.Context, rawListeners []string) (returnErr error) {
	if len(rawListeners) == 0 {
		return fmt.Errorf("at least one listener is required")
	}
	listeners := make([]*managedListener, 0, len(rawListeners))
	for _, raw := range rawListeners {
		listener, err := listen(raw)
		if err != nil {
			var cleanupErr error
			for i := len(listeners) - 1; i >= 0; i-- {
				cleanupErr = errors.Join(cleanupErr, listeners[i].Close())
			}
			return errors.Join(err, cleanupErr)
		}
		listeners = append(listeners, listener)
		log.Printf("colima-desktop daemon listening on %s:%s", listener.spec.network, listener.Addr())
	}
	defer func() {
		for i := len(listeners) - 1; i >= 0; i-- {
			returnErr = errors.Join(returnErr, listeners[i].Close())
		}
	}()

	grpcServer := grpc.NewServer()
	server.Register(grpcServer)
	return serve(ctx, grpcServer, listeners, gracefulStopTimeout)
}

func main() {
	options, err := parseOptions(os.Args[1:], runtime.GOOS, os.Getenv)
	if err != nil {
		log.Fatalf("invalid daemon options: %v", err)
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	if err := run(ctx, options.listen); err != nil {
		log.Fatalf("daemon failed: %v", err)
	}
}
