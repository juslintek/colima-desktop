package server

import (
	"context"
	"errors"
	"io"
	"net"
	"reflect"
	"strings"
	"sync"
	"testing"
	"time"

	pb "github.com/colima-desktop/daemon/proto"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/grpc/status"
	"google.golang.org/grpc/test/bufconn"
)

// dialer spins up an in-memory gRPC server with the real generated service
// registration and returns a connected client — proving the daemon serves
// the ColimaService contract over the wire (bufconn, no real socket).
func newTestClient(t *testing.T, implementations ...pb.ColimaServiceServer) pb.ColimaServiceClient {
	t.Helper()
	lis := bufconn.Listen(1024 * 1024)
	srv := grpc.NewServer()
	implementation := pb.ColimaServiceServer(New())
	if len(implementations) > 0 {
		implementation = implementations[0]
	}
	pb.RegisterColimaServiceServer(srv, implementation)
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

func TestConcurrentStatusRequestsSerializeGlobalProfileSelection(t *testing.T) {
	implementation := New()
	var wait sync.WaitGroup
	for i := 0; i < 12; i++ {
		profile := "race-a"
		if i%2 == 1 {
			profile = "race-b"
		}
		wait.Add(1)
		go func() {
			defer wait.Done()
			if _, err := implementation.Status(context.Background(), &pb.StatusRequest{Profile: profile}); err != nil {
				t.Errorf("Status(%s): %v", profile, err)
			}
		}()
	}
	wait.Wait()
}

func TestListMachinesRPC(t *testing.T) {
	c := newTestClient(t)
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	// May return an empty list or an error if limactl absent; assert it doesn't panic
	// and the RPC round-trips.
	_, _ = c.ListMachines(ctx, &pb.Empty{})
}

type commandCall struct {
	name string
	args []string
}

func recordingRunner(calls chan<- commandCall, output []byte, err error) commandRunner {
	return func(_ context.Context, name string, args ...string) ([]byte, error) {
		calls <- commandCall{name: name, args: append([]string(nil), args...)}
		return output, err
	}
}

func receiveCall(t *testing.T, calls <-chan commandCall) commandCall {
	t.Helper()
	select {
	case call := <-calls:
		return call
	case <-time.After(time.Second):
		t.Fatal("command was not called")
		return commandCall{}
	}
}

func TestProfileNormalization(t *testing.T) {
	tests := []struct {
		input       string
		wantProfile string
		wantContext string
	}{
		{input: "", wantProfile: "default", wantContext: "colima"},
		{input: " colima ", wantProfile: "default", wantContext: "colima"},
		{input: "colima-team", wantProfile: "team", wantContext: "colima-team"},
		{input: "team", wantProfile: "team", wantContext: "colima-team"},
	}
	for _, test := range tests {
		if got := normalizedProfile(test.input); got != test.wantProfile {
			t.Errorf("normalizedProfile(%q) = %q, want %q", test.input, got, test.wantProfile)
		}
		if got := kubeContextForProfile(test.input); got != test.wantContext {
			t.Errorf("kubeContextForProfile(%q) = %q, want %q", test.input, got, test.wantContext)
		}
	}
}

func TestScopedUnaryHandlersPassExplicitProfile(t *testing.T) {
	tests := []struct {
		name     string
		wantArgs []string
		invoke   func(context.Context, pb.ColimaServiceClient) error
	}{
		{
			name:     "Update",
			wantArgs: []string{"--profile", "dev", "update"},
			invoke: func(ctx context.Context, client pb.ColimaServiceClient) error {
				response, err := client.Update(ctx, &pb.ProfileRequest{Profile: "dev"})
				if err == nil && !response.Success {
					return errors.New(response.Error)
				}
				return err
			},
		},
		{
			name:     "Prune",
			wantArgs: []string{"--profile", "dev", "prune", "--force", "--all"},
			invoke: func(ctx context.Context, client pb.ColimaServiceClient) error {
				response, err := client.Prune(ctx, &pb.PruneRequest{Profile: "dev", All: true})
				if err == nil && !response.Success {
					return errors.New(response.Error)
				}
				return err
			},
		},
		{
			name:     "CreateProfile",
			wantArgs: []string{"--profile", "dev", "start", "--cpu", "4", "--runtime", "docker"},
			invoke: func(ctx context.Context, client pb.ColimaServiceClient) error {
				response, err := client.CreateProfile(ctx, &pb.CreateProfileRequest{Name: "dev", Config: &pb.ColimaConfig{Cpu: 4, Runtime: "docker"}})
				if err == nil && !response.Success {
					return errors.New(response.Error)
				}
				return err
			},
		},
		{
			name:     "DeleteProfile",
			wantArgs: []string{"--profile", "dev", "delete", "--force", "--data"},
			invoke: func(ctx context.Context, client pb.ColimaServiceClient) error {
				response, err := client.DeleteProfile(ctx, &pb.DeleteProfileRequest{Name: "dev", Data: true})
				if err == nil && !response.Success {
					return errors.New(response.Error)
				}
				return err
			},
		},
		{
			name:     "CloneProfile",
			wantArgs: []string{"clone", "source", "destination"},
			invoke: func(ctx context.Context, client pb.ColimaServiceClient) error {
				response, err := client.CloneProfile(ctx, &pb.CloneProfileRequest{Source: "source", Destination: "destination"})
				if err == nil && !response.Success {
					return errors.New(response.Error)
				}
				return err
			},
		},
		{
			name:     "SSHConfig",
			wantArgs: []string{"--profile", "dev", "ssh-config"},
			invoke: func(ctx context.Context, client pb.ColimaServiceClient) error {
				_, err := client.SSHConfig(ctx, &pb.ProfileRequest{Profile: "dev"})
				return err
			},
		},
		{
			name:     "KubernetesReset",
			wantArgs: []string{"--profile", "dev", "kubernetes", "reset"},
			invoke: func(ctx context.Context, client pb.ColimaServiceClient) error {
				response, err := client.KubernetesReset(ctx, &pb.ProfileRequest{Profile: "dev"})
				if err == nil && !response.Success {
					return errors.New(response.Error)
				}
				return err
			},
		},
		{
			name:     "KillProcess",
			wantArgs: []string{"--profile", "dev", "ssh", "--", "kill", "-15", "42"},
			invoke: func(ctx context.Context, client pb.ColimaServiceClient) error {
				response, err := client.KillProcess(ctx, &pb.KillProcessRequest{Profile: "dev", Pid: 42, Signal: 15})
				if err == nil && !response.Success {
					return errors.New(response.Error)
				}
				return err
			},
		},
		{
			name:     "UpdateRuntime",
			wantArgs: []string{"--profile", "dev", "update"},
			invoke: func(ctx context.Context, client pb.ColimaServiceClient) error {
				response, err := client.UpdateRuntime(ctx, &pb.ProfileRequest{Profile: "dev"})
				if err == nil && !response.Success {
					return errors.New(response.Error)
				}
				return err
			},
		},
		{
			name:     "SwitchRuntime",
			wantArgs: []string{"--profile", "dev", "start", "--runtime", "containerd"},
			invoke: func(ctx context.Context, client pb.ColimaServiceClient) error {
				response, err := client.SwitchRuntime(ctx, &pb.SwitchRuntimeRequest{Profile: "dev", Runtime: "containerd"})
				if err == nil && !response.Success {
					return errors.New(response.Error)
				}
				return err
			},
		},
		{
			name:     "ModelServe",
			wantArgs: []string{"--profile", "dev", "model", "--runner", "ramalama", "serve", "model-name", "--port", "8081"},
			invoke: func(ctx context.Context, client pb.ColimaServiceClient) error {
				response, err := client.ModelServe(ctx, &pb.ModelServeRequest{Profile: "dev", Runner: "ramalama", Model: "model-name", Port: 8081})
				if err == nil && !response.Success {
					return errors.New(response.Error)
				}
				return err
			},
		},
		{
			name:     "ModelStop",
			wantArgs: []string{"--profile", "dev", "ssh", "--", "sh", "-c", modelStopScript},
			invoke: func(ctx context.Context, client pb.ColimaServiceClient) error {
				response, err := client.ModelStop(ctx, &pb.ProfileRequest{Profile: "dev"})
				if err == nil && (!response.Success || !strings.Contains(response.Message, "stopped")) {
					return errors.New(response.Error)
				}
				return err
			},
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			calls := make(chan commandCall, 1)
			implementation := New()
			implementation.commandRunner = recordingRunner(calls, []byte("ok"), nil)
			client := newTestClient(t, implementation)
			ctx, cancel := context.WithTimeout(context.Background(), time.Second)
			defer cancel()
			if err := test.invoke(ctx, client); err != nil {
				t.Fatalf("invoke: %v", err)
			}
			call := receiveCall(t, calls)
			if call.name != "colima" || !reflect.DeepEqual(call.args, test.wantArgs) {
				t.Fatalf("command = %s %#v, want colima %#v", call.name, call.args, test.wantArgs)
			}
		})
	}
}

func TestScopedUnaryHandlerPropagatesCommandFailure(t *testing.T) {
	implementation := New()
	implementation.commandRunner = func(context.Context, string, ...string) ([]byte, error) {
		return []byte("profile unavailable"), errors.New("exit 1")
	}
	client := newTestClient(t, implementation)
	response, err := client.ModelStop(context.Background(), &pb.ProfileRequest{Profile: "missing"})
	if err != nil {
		t.Fatalf("ModelStop transport error: %v", err)
	}
	if response.Success || !strings.Contains(response.Error, "profile unavailable") {
		t.Fatalf("response = %#v", response)
	}
}

func TestUpdateAndPruneReturnContextualCommandFailures(t *testing.T) {
	implementation := New()
	implementation.commandRunner = func(_ context.Context, _ string, _ ...string) ([]byte, error) {
		return []byte("profile unavailable"), errors.New("exit 1")
	}
	client := newTestClient(t, implementation)
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()

	update, err := client.Update(ctx, &pb.ProfileRequest{Profile: "dev"})
	if err != nil || update.Success || !strings.Contains(update.Error, "colima --profile dev update") || !strings.Contains(update.Error, "profile unavailable") {
		t.Fatalf("Update = %#v, err=%v", update, err)
	}
	prune, err := client.Prune(ctx, &pb.PruneRequest{Profile: "dev", All: true})
	if err != nil || prune.Success || !strings.Contains(prune.Error, "colima --profile dev prune --force --all") || !strings.Contains(prune.Error, "profile unavailable") {
		t.Fatalf("Prune = %#v, err=%v", prune, err)
	}
}

func TestUpdateHonorsRequestCancellation(t *testing.T) {
	implementation := New()
	implementation.commandRunner = func(ctx context.Context, _ string, _ ...string) ([]byte, error) {
		<-ctx.Done()
		return nil, ctx.Err()
	}
	client := newTestClient(t, implementation)
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	_, err := client.Update(ctx, &pb.ProfileRequest{Profile: "dev"})
	if status.Code(err) != codes.Canceled {
		t.Fatalf("Update error = %v (%s), want Canceled", err, status.Code(err))
	}
}

type fakeExitError struct {
	code int
}

func (err fakeExitError) Error() string { return "command failed" }
func (err fakeExitError) ExitCode() int { return err.code }

func TestKubernetesExecUsesProfileContextAndReportsErrors(t *testing.T) {
	t.Run("success and quoted arguments", func(t *testing.T) {
		calls := make(chan commandCall, 1)
		implementation := New()
		implementation.commandRunner = recordingRunner(calls, []byte("pod-a\n"), nil)
		client := newTestClient(t, implementation)
		response, err := client.KubernetesExec(context.Background(), &pb.KubeExecRequest{
			Profile: "team",
			Command: `get pods -l "app=my app"`,
		})
		if err != nil || response.Error != "" || response.ExitCode != 0 {
			t.Fatalf("response=%#v err=%v", response, err)
		}
		call := receiveCall(t, calls)
		want := []string{"get", "pods", "-l", "app=my app", "--context", "colima-team"}
		if call.name != "kubectl" || !reflect.DeepEqual(call.args, want) {
			t.Fatalf("command = %s %#v, want kubectl %#v", call.name, call.args, want)
		}
	})

	t.Run("exit error", func(t *testing.T) {
		implementation := New()
		implementation.commandRunner = func(context.Context, string, ...string) ([]byte, error) {
			return []byte("not found"), fakeExitError{code: 7}
		}
		client := newTestClient(t, implementation)
		response, err := client.KubernetesExec(context.Background(), &pb.KubeExecRequest{Command: "get missing"})
		if err != nil || response.ExitCode != 7 || !strings.Contains(response.Error, "not found") {
			t.Fatalf("response=%#v err=%v", response, err)
		}
	})

	t.Run("invalid command", func(t *testing.T) {
		client := newTestClient(t, New())
		response, err := client.KubernetesExec(context.Background(), &pb.KubeExecRequest{Command: `get "unterminated`})
		if err != nil || response.ExitCode != -1 || response.Error == "" {
			t.Fatalf("response=%#v err=%v", response, err)
		}
	})
}

func TestKubernetesExecCancellationReachesCommand(t *testing.T) {
	commandStarted := make(chan struct{})
	implementation := New()
	implementation.commandRunner = func(ctx context.Context, _ string, _ ...string) ([]byte, error) {
		close(commandStarted)
		<-ctx.Done()
		return nil, ctx.Err()
	}
	client := newTestClient(t, implementation)
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() {
		_, err := client.KubernetesExec(ctx, &pb.KubeExecRequest{Profile: "dev", Command: "get pods"})
		done <- err
	}()
	select {
	case <-commandStarted:
	case <-time.After(time.Second):
		t.Fatal("command did not start")
	}
	cancel()
	select {
	case err := <-done:
		if status.Code(err) != codes.Canceled {
			t.Fatalf("error = %v (%s), want Canceled", err, status.Code(err))
		}
	case <-time.After(time.Second):
		t.Fatal("RPC did not cancel")
	}
}

func TestProcessListParsesDataAndPropagatesFailures(t *testing.T) {
	const processOutput = "root 123 12.5 3.5 100 20 ? S 10:00 0:01 /usr/bin/example --flag\n"
	t.Run("success", func(t *testing.T) {
		calls := make(chan commandCall, 1)
		implementation := New()
		implementation.commandRunner = recordingRunner(calls, []byte(processOutput), nil)
		client := newTestClient(t, implementation)
		response, err := client.ProcessList(context.Background(), &pb.ProfileRequest{Profile: "processes"})
		if err != nil {
			t.Fatalf("ProcessList: %v", err)
		}
		if len(response.Processes) != 1 {
			t.Fatalf("processes = %#v", response.Processes)
		}
		process := response.Processes[0]
		if process.Pid != 123 || process.CpuPercent != 12.5 || process.MemoryPercent != 3.5 || process.Command != "/usr/bin/example --flag" {
			t.Fatalf("process = %#v", process)
		}
		call := receiveCall(t, calls)
		if !reflect.DeepEqual(call.args[:2], []string{"--profile", "processes"}) {
			t.Fatalf("args = %#v", call.args)
		}
	})

	tests := []struct {
		name   string
		output string
		err    error
		want   string
	}{
		{name: "command error", output: "ssh unavailable", err: errors.New("exit 1"), want: "ssh unavailable"},
		{name: "parse error", output: "malformed", want: "expected at least 11 fields"},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			implementation := New()
			implementation.commandRunner = func(context.Context, string, ...string) ([]byte, error) {
				return []byte(test.output), test.err
			}
			client := newTestClient(t, implementation)
			_, err := client.ProcessList(context.Background(), &pb.ProfileRequest{})
			if status.Code(err) != codes.Unknown || !strings.Contains(err.Error(), test.want) {
				t.Fatalf("error = %v (%s), want Unknown containing %q", err, status.Code(err), test.want)
			}
		})
	}
}

func receiveProgressEvents(t *testing.T, stream interface {
	Recv() (*pb.ProgressEvent, error)
}) []*pb.ProgressEvent {
	t.Helper()
	var events []*pb.ProgressEvent
	for {
		event, err := stream.Recv()
		if err == io.EOF {
			return events
		}
		if err != nil {
			t.Fatalf("receive stream: %v", err)
		}
		events = append(events, event)
	}
}

func TestModelStreamsUseProfileAndPropagateProgress(t *testing.T) {
	tests := []struct {
		name     string
		wantArgs []string
		invoke   func(pb.ColimaServiceClient) (interface {
			Recv() (*pb.ProgressEvent, error)
		}, error)
	}{
		{
			name:     "setup",
			wantArgs: []string{"--profile", "models", "model", "--runner", "ramalama", "setup"},
			invoke: func(client pb.ColimaServiceClient) (interface {
				Recv() (*pb.ProgressEvent, error)
			}, error) {
				return client.ModelSetup(context.Background(), &pb.ModelRequest{Profile: "models", Runner: "ramalama"})
			},
		},
		{
			name:     "run",
			wantArgs: []string{"--profile", "models", "model", "--runner", "docker", "run", "ai/test", "hello world"},
			invoke: func(client pb.ColimaServiceClient) (interface {
				Recv() (*pb.ProgressEvent, error)
			}, error) {
				return client.ModelRun(context.Background(), &pb.ModelRunRequest{Profile: "models", Model: "ai/test", Prompt: "hello world"})
			},
		},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			calls := make(chan commandCall, 1)
			implementation := New()
			implementation.lineCommandRunner = func(_ context.Context, name string, args []string, onLine func(string) error) error {
				calls <- commandCall{name: name, args: append([]string(nil), args...)}
				return onLine("working")
			}
			client := newTestClient(t, implementation)
			stream, err := test.invoke(client)
			if err != nil {
				t.Fatalf("start stream: %v", err)
			}
			events := receiveProgressEvents(t, stream)
			if len(events) != 2 || events[0].Message != "working" || !events[1].Done {
				t.Fatalf("events = %#v", events)
			}
			call := receiveCall(t, calls)
			if call.name != "colima" || !reflect.DeepEqual(call.args, test.wantArgs) {
				t.Fatalf("command = %s %#v, want colima %#v", call.name, call.args, test.wantArgs)
			}
		})
	}
}

func TestModelStreamReportsCommandError(t *testing.T) {
	implementation := New()
	implementation.lineCommandRunner = func(context.Context, string, []string, func(string) error) error {
		return errors.New("runner unavailable")
	}
	client := newTestClient(t, implementation)
	stream, err := client.ModelRun(context.Background(), &pb.ModelRunRequest{Profile: "models", Model: "ai/test"})
	if err != nil {
		t.Fatalf("start stream: %v", err)
	}
	events := receiveProgressEvents(t, stream)
	if len(events) != 1 || !events[0].Done || !strings.Contains(events[0].Error, "runner unavailable") {
		t.Fatalf("events = %#v", events)
	}
}

func TestModelStreamCancellationReachesCommand(t *testing.T) {
	commandStarted := make(chan struct{})
	commandCancelled := make(chan struct{})
	var startOnce, closeOnce sync.Once
	implementation := New()
	implementation.lineCommandRunner = func(ctx context.Context, _ string, _ []string, _ func(string) error) error {
		startOnce.Do(func() { close(commandStarted) })
		<-ctx.Done()
		closeOnce.Do(func() { close(commandCancelled) })
		return ctx.Err()
	}
	client := newTestClient(t, implementation)
	ctx, cancel := context.WithCancel(context.Background())
	stream, err := client.ModelSetup(ctx, &pb.ModelRequest{Profile: "models"})
	if err != nil {
		t.Fatalf("start stream: %v", err)
	}
	select {
	case <-commandStarted:
	case <-time.After(time.Second):
		t.Fatal("command did not start")
	}
	cancel()
	if _, err := stream.Recv(); status.Code(err) != codes.Canceled {
		t.Fatalf("receive error = %v (%s), want Canceled", err, status.Code(err))
	}
	select {
	case <-commandCancelled:
	case <-time.After(time.Second):
		t.Fatal("command did not observe cancellation")
	}
}

const firstVMSample = "cpu 100 50\nmem 1000 400\ndisk 10000 2500\ntime 100\n"
const secondVMSample = "cpu 200 70\nmem 1000 300\ndisk 10000 3000\ntime 101\n"

func TestVMStatsStreamsPeriodicSamplesAndCancels(t *testing.T) {
	implementation := New()
	implementation.statsInterval = time.Millisecond
	var mu sync.Mutex
	callCount := 0
	var calls []commandCall
	implementation.commandRunner = func(_ context.Context, name string, args ...string) ([]byte, error) {
		mu.Lock()
		defer mu.Unlock()
		calls = append(calls, commandCall{name: name, args: append([]string(nil), args...)})
		callCount++
		if callCount == 1 {
			return []byte(firstVMSample), nil
		}
		return []byte(secondVMSample), nil
	}
	client := newTestClient(t, implementation)
	ctx, cancel := context.WithCancel(context.Background())
	stream, err := client.VMStats(ctx, &pb.ProfileRequest{Profile: "metrics"})
	if err != nil {
		t.Fatalf("start stream: %v", err)
	}
	first, err := stream.Recv()
	if err != nil {
		t.Fatalf("first event: %v", err)
	}
	second, err := stream.Recv()
	if err != nil {
		t.Fatalf("second event: %v", err)
	}
	if first.MemoryTotal != 1000*1024 || first.MemoryUsed != 600*1024 || first.DiskUsed != 2500 {
		t.Fatalf("first event = %#v", first)
	}
	if second.CpuPercent != 80 || second.MemoryUsed != 700*1024 || second.Timestamp != 101 {
		t.Fatalf("second event = %#v", second)
	}
	cancel()
	if _, err := stream.Recv(); status.Code(err) != codes.Canceled {
		t.Fatalf("receive after cancel = %v (%s), want Canceled", err, status.Code(err))
	}
	mu.Lock()
	defer mu.Unlock()
	if len(calls) < 2 || !reflect.DeepEqual(calls[0].args[:2], []string{"--profile", "metrics"}) {
		t.Fatalf("calls = %#v", calls)
	}
}

func TestVMStatsPropagatesCommandAndParseErrors(t *testing.T) {
	tests := []struct {
		name   string
		output string
		err    error
		want   string
	}{
		{name: "command", output: "vm unavailable", err: errors.New("exit 1"), want: "vm unavailable"},
		{name: "parse", output: "cpu bad data\n", want: "parse VM CPU total"},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			implementation := New()
			implementation.commandRunner = func(context.Context, string, ...string) ([]byte, error) {
				return []byte(test.output), test.err
			}
			client := newTestClient(t, implementation)
			stream, err := client.VMStats(context.Background(), &pb.ProfileRequest{})
			if err != nil {
				t.Fatalf("start stream: %v", err)
			}
			_, err = stream.Recv()
			if status.Code(err) != codes.Unknown || !strings.Contains(err.Error(), test.want) {
				t.Fatalf("error = %v (%s), want Unknown containing %q", err, status.Code(err), test.want)
			}
		})
	}
}

func TestEffectiveRuntimeFallsBackToPersistedConfig(t *testing.T) {
	tests := []struct {
		name            string
		instanceRuntime string
		configRuntime   string
		want            string
	}{
		{name: "instance value wins", instanceRuntime: " docker ", configRuntime: "containerd", want: "docker"},
		{name: "single-instance fallback", configRuntime: " docker ", want: "docker"},
		{name: "empty stays empty", want: ""},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if got := effectiveRuntime(test.instanceRuntime, test.configRuntime); got != test.want {
				t.Fatalf("effectiveRuntime(%q, %q) = %q, want %q", test.instanceRuntime, test.configRuntime, got, test.want)
			}
		})
	}
}
