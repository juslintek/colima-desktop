package server

// Feature: cross-platform-live-verification, Property 10 & 11
//
// Daemon request-scoping property tests (design Property 10 & 11; Requirements
// 3.4, 3.5). The unit under test is task 2.4's scope machinery:
//
//   - requireProfile / requireScopeField / requireDockerScope (command.go)
//   - colimaProfileArgs + normalizedProfile targeting (command.go)
//   - docker.Target.SocketPath() profile-scoped socket (internal/docker)
//   - mutatingClientFor vs clientFor read/mutate split (docker_server.go)
//   - their wiring into the mutating ColimaService / DockerService RPCs.
//
// These tests never modify production code. If a property fails, the failure
// message prints the exact counterexample (seed + iteration + input) so the
// underlying bug can be reported rather than the test weakened.
//
// In-package helpers reused from server_test.go / docker_server_test.go:
//   newTestClient, newDockerClient, recordingRunner, commandCall, receiveCall,
//   fakeImageClient, receiveProgress, imageRPCs, progressReceiver.

import (
	"context"
	"io"
	"math/rand"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/colima-desktop/daemon/internal/docker"
	pb "github.com/colima-desktop/daemon/proto"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// propIters is the number of randomized iterations each property runs. The
// design mandates a minimum of 100; 128 keeps a comfortable margin and, with
// round-robin invoker selection, guarantees every RPC in a table is exercised.
const propIters = 128

// ─── randomized generators over the profile input space ─────────────────────

const alnumChars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

// randName builds a random, realistic profile token: a leading alphanumeric
// followed by alphanumerics, dashes, underscores, and dots. It never yields "",
// ".", "..", or a whitespace-only string, so it is always a valid scope target.
func randName(rng *rand.Rand) string {
	const rest = alnumChars + "-_."
	n := 1 + rng.Intn(12)
	b := make([]byte, n)
	b[0] = alnumChars[rng.Intn(len(alnumChars))]
	for i := 1; i < n; i++ {
		b[i] = rest[rng.Intn(len(rest))]
	}
	return string(b)
}

// randScopedProfile returns a non-empty profile that "carries P": explicit
// "default"/"colima", a "colima-"-prefixed name, a random valid name, or a
// space-padded name (whose trimmed content is still non-empty).
func randScopedProfile(rng *rand.Rand) string {
	switch rng.Intn(6) {
	case 0:
		return "default"
	case 1:
		return "colima"
	case 2:
		return "colima-" + randName(rng)
	case 3:
		return " " + randName(rng) + " "
	default:
		return randName(rng)
	}
}

// randOmittedProfile returns a blank / whitespace-only profile — the "omitted
// required scope field" case that safe scoping must reject.
func randOmittedProfile(rng *rand.Rand) string {
	options := []string{"", " ", "  ", "\t", "\n", " \t ", "\t\n ", "   \t"}
	return options[rng.Intn(len(options))]
}

// randDockerDirProfile returns a non-empty directory-style profile name for the
// docker socket path (docker.Target does not normalize, so the literal name is
// the socket directory).
func randDockerDirProfile(rng *rand.Rand) string {
	switch rng.Intn(4) {
	case 0:
		return "default"
	case 1:
		return "colima"
	case 2:
		return "colima-" + randName(rng)
	default:
		return randName(rng)
	}
}

// randHost randomly returns "" (local) or a remote-SSH host. Host must never
// relax the docker scope guard (only the WSL2 provider does), so mixing it in
// strengthens Property 11.
func randHost(rng *rand.Rand) string {
	if rng.Intn(2) == 0 {
		return ""
	}
	return "user@" + randName(rng) + ".test"
}

// ─── shared assertions ──────────────────────────────────────────────────────

func assertContextualInvalidArgument(t *testing.T, where string, err error, wantSubstr string) {
	t.Helper()
	if status.Code(err) != codes.InvalidArgument {
		t.Fatalf("%s: code = %s (err=%v), want InvalidArgument", where, status.Code(err), err)
	}
	msg := status.Convert(err).Message()
	if strings.TrimSpace(msg) == "" {
		t.Fatalf("%s: rejected with an empty (non-contextual) message", where)
	}
	if wantSubstr != "" && !strings.Contains(msg, wantSubstr) {
		t.Fatalf("%s: message %q missing contextual substring %q", where, msg, wantSubstr)
	}
}

func sameArgs(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

// ============================================================================
// Property 10 — Profile-scoped command targeting
// A profile-scoped request carrying profile P targets exactly P, never a
// default/global/implicit target.
// ============================================================================

// TestProperty10_ColimaProfileArgsTargetsExactProfile asserts colimaProfileArgs
// always emits `--profile <normalizedProfile(P)>` (a non-empty, explicit target)
// followed by the caller's args unchanged, for any scoped profile.
//
// Feature: cross-platform-live-verification, Property 10
func TestProperty10_ColimaProfileArgsTargetsExactProfile(t *testing.T) {
	const seed = int64(0x10a)
	rng := rand.New(rand.NewSource(seed))
	for i := 0; i < propIters; i++ {
		p := randScopedProfile(rng)
		extra := make([]string, rng.Intn(4))
		for j := range extra {
			extra[j] = randName(rng)
		}

		got := colimaProfileArgs(p, extra...)
		want := normalizedProfile(p)

		if strings.TrimSpace(want) == "" {
			t.Fatalf("Property 10 counterexample (seed=%d iter=%d): normalizedProfile(%q) is empty — a scoped request would target the implicit default", seed, i, p)
		}
		if len(got) < 2 || got[0] != "--profile" {
			t.Fatalf("Property 10 counterexample (seed=%d iter=%d): colimaProfileArgs(%q,%v) = %#v — missing leading `--profile <P>`", seed, i, p, extra, got)
		}
		if got[1] != want {
			t.Fatalf("Property 10 counterexample (seed=%d iter=%d): colimaProfileArgs(%q) targets %q, want %q", seed, i, p, got[1], want)
		}
		if !sameArgs(got[2:], extra) {
			t.Fatalf("Property 10 counterexample (seed=%d iter=%d): trailing args = %#v, want %#v (scope flag must not drop/reorder args)", seed, i, got[2:], extra)
		}
	}
}

// TestProperty10_DockerTargetResolvesProfileScopedSocket asserts a docker
// request carrying profile P resolves the P-scoped unix socket
// (~/.colima/P/docker.sock), never the bare default socket unless P == default.
//
// Feature: cross-platform-live-verification, Property 10
func TestProperty10_DockerTargetResolvesProfileScopedSocket(t *testing.T) {
	const seed = int64(0x10b)
	rng := rand.New(rand.NewSource(seed))
	home, _ := os.UserHomeDir() // SocketPath ignores the error; mirror it exactly.
	defaultSocket := filepath.Join(home, ".colima", "default", "docker.sock")

	for i := 0; i < propIters; i++ {
		p := randDockerDirProfile(rng)
		got := docker.Target{Profile: p}.SocketPath()
		want := filepath.Join(home, ".colima", p, "docker.sock")

		if got != want {
			t.Fatalf("Property 10 counterexample (seed=%d iter=%d): Target{Profile:%q}.SocketPath() = %q, want %q", seed, i, p, got, want)
		}
		if !strings.HasSuffix(got, filepath.Join(".colima", p, "docker.sock")) {
			t.Fatalf("Property 10 counterexample (seed=%d iter=%d): socket %q is not scoped under profile %q", seed, i, got, p)
		}
		if p != "default" && got == defaultSocket {
			t.Fatalf("Property 10 counterexample (seed=%d iter=%d): profile %q resolved to the default socket %q", seed, i, p, defaultSocket)
		}
	}
}

// TestProperty10_MutatingColimaRPCsTargetRequestedProfile drives the mutating
// ColimaService RPCs over bufconn with a recording runner and asserts each
// builds `colima --profile <normalizedProfile(P)> …` for a random profile P —
// end-to-end proof that the wired handlers target the requested profile.
//
// Feature: cross-platform-live-verification, Property 10
func TestProperty10_MutatingColimaRPCsTargetRequestedProfile(t *testing.T) {
	const seed = int64(0x10c)
	rng := rand.New(rand.NewSource(seed))

	calls := make(chan commandCall, 4)
	impl := New()
	impl.commandRunner = recordingRunner(calls, []byte("ok"), nil)
	client := newTestClient(t, impl)

	// Each invoker feeds the random profile into its profile-bearing field and
	// runs a colima command through the recording runner.
	invokers := []struct {
		name string
		call func(ctx context.Context, c pb.ColimaServiceClient, profile string) error
	}{
		{"Update", func(ctx context.Context, c pb.ColimaServiceClient, p string) error {
			_, err := c.Update(ctx, &pb.ProfileRequest{Profile: p})
			return err
		}},
		{"Prune", func(ctx context.Context, c pb.ColimaServiceClient, p string) error {
			_, err := c.Prune(ctx, &pb.PruneRequest{Profile: p})
			return err
		}},
		{"UpdateRuntime", func(ctx context.Context, c pb.ColimaServiceClient, p string) error {
			_, err := c.UpdateRuntime(ctx, &pb.ProfileRequest{Profile: p})
			return err
		}},
		{"SwitchRuntime", func(ctx context.Context, c pb.ColimaServiceClient, p string) error {
			_, err := c.SwitchRuntime(ctx, &pb.SwitchRuntimeRequest{Profile: p, Runtime: "docker"})
			return err
		}},
		{"KubernetesReset", func(ctx context.Context, c pb.ColimaServiceClient, p string) error {
			_, err := c.KubernetesReset(ctx, &pb.ProfileRequest{Profile: p})
			return err
		}},
		{"KillProcess", func(ctx context.Context, c pb.ColimaServiceClient, p string) error {
			_, err := c.KillProcess(ctx, &pb.KillProcessRequest{Profile: p, Pid: 1})
			return err
		}},
		{"ModelServe", func(ctx context.Context, c pb.ColimaServiceClient, p string) error {
			_, err := c.ModelServe(ctx, &pb.ModelServeRequest{Profile: p})
			return err
		}},
		{"ModelStop", func(ctx context.Context, c pb.ColimaServiceClient, p string) error {
			_, err := c.ModelStop(ctx, &pb.ProfileRequest{Profile: p})
			return err
		}},
		{"CreateProfile", func(ctx context.Context, c pb.ColimaServiceClient, p string) error {
			_, err := c.CreateProfile(ctx, &pb.CreateProfileRequest{Name: p})
			return err
		}},
		{"DeleteProfile", func(ctx context.Context, c pb.ColimaServiceClient, p string) error {
			_, err := c.DeleteProfile(ctx, &pb.DeleteProfileRequest{Name: p})
			return err
		}},
	}

	ctx := context.Background()
	for i := 0; i < propIters; i++ {
		inv := invokers[i%len(invokers)]
		p := randScopedProfile(rng)

		if err := inv.call(ctx, client, p); err != nil {
			t.Fatalf("Property 10 counterexample (seed=%d iter=%d rpc=%s profile=%q): unexpected transport error: %v", seed, i, inv.name, p, err)
		}
		call := receiveCall(t, calls)
		want := normalizedProfile(p)
		if call.name != "colima" || len(call.args) < 2 || call.args[0] != "--profile" || call.args[1] != want {
			t.Fatalf("Property 10 counterexample (seed=%d iter=%d rpc=%s profile=%q): built %s %#v, want leading `colima --profile %s`", seed, i, inv.name, p, call.name, call.args, want)
		}
	}
}

// TestProperty10_ImageStreamsForwardProfileScopedTarget asserts PullImage /
// PushImage forward a docker.Target scoped to the requested profile P (never a
// default/global target) via the injected image-client factory.
//
// Feature: cross-platform-live-verification, Property 10
func TestProperty10_ImageStreamsForwardProfileScopedTarget(t *testing.T) {
	const seed = int64(0x10d)
	rng := rand.New(rand.NewSource(seed))

	client, targets := newImageTargetServer(t)
	rpcs := imageRPCs()
	ops := []struct {
		name string
		fn   imageRPC
	}{
		{"pull", rpcs["pull"]},
		{"push", rpcs["push"]},
	}

	ctx := context.Background()
	for i := 0; i < propIters; i++ {
		op := ops[i%len(ops)]
		p := randScopedProfile(rng)

		stream, err := op.fn(client, ctx, &pb.NameRequest{Name: "alpine:latest", Profile: p})
		if err != nil {
			t.Fatalf("Property 10 counterexample (seed=%d iter=%d op=%s profile=%q): start stream: %v", seed, i, op.name, p, err)
		}
		events := receiveProgress(t, stream)
		if len(events) == 0 || !events[len(events)-1].Done {
			t.Fatalf("Property 10 counterexample (seed=%d iter=%d op=%s profile=%q): missing terminal event: %#v", seed, i, op.name, p, events)
		}

		select {
		case tgt := <-targets:
			if tgt.Profile != p {
				t.Fatalf("Property 10 counterexample (seed=%d iter=%d op=%s): image target profile = %q, want %q", seed, i, op.name, tgt.Profile, p)
			}
			if tgt.WSL2 || tgt.Host != "" {
				t.Fatalf("Property 10 counterexample (seed=%d iter=%d op=%s profile=%q): target drifted off the local profile scope: %#v", seed, i, op.name, p, tgt)
			}
			if !strings.HasSuffix(tgt.SocketPath(), filepath.Join(".colima", p, "docker.sock")) {
				t.Fatalf("Property 10 counterexample (seed=%d iter=%d op=%s): target socket %q not scoped under %q", seed, i, op.name, tgt.SocketPath(), p)
			}
		default:
			t.Fatalf("Property 10 counterexample (seed=%d iter=%d op=%s profile=%q): factory was never invoked — no scoped docker call was made", seed, i, op.name, p)
		}
	}
}

// ============================================================================
// Property 11 — Unscoped-request rejection
// A request omitting a required profile/provider scope field is rejected with a
// contextual InvalidArgument error and never executes against global state.
// WSL2-only docker scope is allowed; reads keep the default fallback.
// ============================================================================

// TestProperty11_RequireProfileRejectsOmittedAllowsPresent — direct helper.
//
// Feature: cross-platform-live-verification, Property 11
func TestProperty11_RequireProfileRejectsOmittedAllowsPresent(t *testing.T) {
	const seed = int64(0x11a)
	rng := rand.New(rand.NewSource(seed))
	for i := 0; i < propIters; i++ {
		if rng.Intn(2) == 0 {
			p := randOmittedProfile(rng)
			err := requireProfile(p)
			if err == nil {
				t.Fatalf("Property 11 counterexample (seed=%d iter=%d): requireProfile(%q) accepted an omitted profile", seed, i, p)
			}
			assertContextualInvalidArgument(t, "requireProfile omitted", err, "required")
		} else {
			p := randScopedProfile(rng)
			if err := requireProfile(p); err != nil {
				t.Fatalf("Property 11 counterexample (seed=%d iter=%d): requireProfile(%q) rejected a present profile: %v", seed, i, p, err)
			}
		}
	}
}

// TestProperty11_RequireScopeFieldRejectsOmittedAllowsPresent — direct helper.
//
// Feature: cross-platform-live-verification, Property 11
func TestProperty11_RequireScopeFieldRejectsOmittedAllowsPresent(t *testing.T) {
	const seed = int64(0x11b)
	rng := rand.New(rand.NewSource(seed))
	fields := []string{"profile name", "clone source profile", "clone destination profile"}
	for i := 0; i < propIters; i++ {
		field := fields[rng.Intn(len(fields))]
		if rng.Intn(2) == 0 {
			v := randOmittedProfile(rng)
			err := requireScopeField(v, field)
			if err == nil {
				t.Fatalf("Property 11 counterexample (seed=%d iter=%d): requireScopeField(%q,%q) accepted an omitted value", seed, i, v, field)
			}
			assertContextualInvalidArgument(t, "requireScopeField omitted", err, "required")
			if !strings.Contains(status.Convert(err).Message(), field) {
				t.Fatalf("Property 11 counterexample (seed=%d iter=%d): requireScopeField error %q does not name the field %q", seed, i, status.Convert(err).Message(), field)
			}
		} else {
			v := randScopedProfile(rng)
			if err := requireScopeField(v, field); err != nil {
				t.Fatalf("Property 11 counterexample (seed=%d iter=%d): requireScopeField(%q,%q) rejected a present value: %v", seed, i, v, field, err)
			}
		}
	}
}

// TestProperty11_RequireDockerScopeRejectsUnlessProfileOrWSL2 — direct helper.
// wsl2-only scope is allowed; a blank profile without WSL2 is rejected.
//
// Feature: cross-platform-live-verification, Property 11
func TestProperty11_RequireDockerScopeRejectsUnlessProfileOrWSL2(t *testing.T) {
	const seed = int64(0x11c)
	rng := rand.New(rand.NewSource(seed))
	for i := 0; i < propIters; i++ {
		switch rng.Intn(3) {
		case 0: // wsl2 true, any profile → allowed
			p := randOmittedProfile(rng)
			if rng.Intn(2) == 0 {
				p = randScopedProfile(rng)
			}
			if err := requireDockerScope(p, true); err != nil {
				t.Fatalf("Property 11 counterexample (seed=%d iter=%d): requireDockerScope(%q,true) rejected a WSL2-scoped request: %v", seed, i, p, err)
			}
		case 1: // wsl2 false, omitted profile → rejected
			p := randOmittedProfile(rng)
			err := requireDockerScope(p, false)
			if err == nil {
				t.Fatalf("Property 11 counterexample (seed=%d iter=%d): requireDockerScope(%q,false) accepted an unscoped docker request", seed, i, p)
			}
			assertContextualInvalidArgument(t, "requireDockerScope unscoped", err, "not safely scoped")
		default: // wsl2 false, present profile → allowed
			p := randScopedProfile(rng)
			if err := requireDockerScope(p, false); err != nil {
				t.Fatalf("Property 11 counterexample (seed=%d iter=%d): requireDockerScope(%q,false) rejected a profile-scoped request: %v", seed, i, p, err)
			}
		}
	}
}

// TestProperty11_ReadPathFallsBackWhileMutatePathRejects contrasts the docker
// read builder (clientFor — keeps the empty→default fallback, never rejected)
// with the mutating builder (mutatingClientFor — rejects an unscoped request).
//
// Feature: cross-platform-live-verification, Property 11
func TestProperty11_ReadPathFallsBackWhileMutatePathRejects(t *testing.T) {
	const seed = int64(0x11d)
	rng := rand.New(rand.NewSource(seed))
	// host is fixed local ("") here: a remote-SSH host would fail transport
	// setup (an SSH-agent error, not a scope rejection) and confuse the
	// read/accept assertions. The guard's host-independence is covered by the
	// end-to-end docker RPC rejection test, where rejection precedes transport.
	for i := 0; i < propIters; i++ {
		// Read path: an omitted profile must NOT be rejected (default fallback).
		omitted := randOmittedProfile(rng)
		if c, err := clientFor(omitted, "", false); err != nil || c == nil {
			t.Fatalf("Property 11 counterexample (seed=%d iter=%d): clientFor(%q,\"\",false) read path rejected the default fallback: client=%v err=%v", seed, i, omitted, c, err)
		}

		// Mutate path: the same omitted profile must be rejected.
		if c, err := mutatingClientFor(omitted, "", false); err == nil || c != nil {
			t.Fatalf("Property 11 counterexample (seed=%d iter=%d): mutatingClientFor(%q,\"\",false) accepted an unscoped mutation (client=%v)", seed, i, omitted, c)
		} else {
			assertContextualInvalidArgument(t, "mutatingClientFor unscoped", err, "not safely scoped")
		}

		// Mutate path with a present profile must be accepted (local socket).
		present := randScopedProfile(rng)
		if c, err := mutatingClientFor(present, "", false); err != nil || c == nil {
			t.Fatalf("Property 11 counterexample (seed=%d iter=%d): mutatingClientFor(%q,\"\",false) rejected a profile-scoped mutation: client=%v err=%v", seed, i, present, c, err)
		}
	}
}

// TestProperty11_MutatingColimaUnaryRPCsRejectOmittedProfile drives the mutating
// unary ColimaService RPCs over bufconn with an omitted profile and asserts each
// is rejected with a contextual InvalidArgument error AND executes no command.
//
// Feature: cross-platform-live-verification, Property 11
func TestProperty11_MutatingColimaUnaryRPCsRejectOmittedProfile(t *testing.T) {
	const seed = int64(0x11e)
	rng := rand.New(rand.NewSource(seed))

	cmdCalls := make(chan commandCall, 8)
	lineCalls := make(chan commandCall, 8)
	impl := New()
	impl.commandRunner = recordingRunner(cmdCalls, []byte("ok"), nil)
	impl.lineCommandRunner = func(_ context.Context, name string, args []string, onLine func(string) error) error {
		lineCalls <- commandCall{name: name, args: append([]string(nil), args...)}
		return onLine("line")
	}
	client := newTestClient(t, impl)

	invokers := []struct {
		name string
		call func(ctx context.Context, c pb.ColimaServiceClient, profile string) error
	}{
		{"Update", func(ctx context.Context, c pb.ColimaServiceClient, p string) error {
			_, err := c.Update(ctx, &pb.ProfileRequest{Profile: p})
			return err
		}},
		{"Prune", func(ctx context.Context, c pb.ColimaServiceClient, p string) error {
			_, err := c.Prune(ctx, &pb.PruneRequest{Profile: p})
			return err
		}},
		{"Stop", func(ctx context.Context, c pb.ColimaServiceClient, p string) error {
			_, err := c.Stop(ctx, &pb.StopRequest{Profile: p})
			return err
		}},
		{"Delete", func(ctx context.Context, c pb.ColimaServiceClient, p string) error {
			_, err := c.Delete(ctx, &pb.DeleteRequest{Profile: p})
			return err
		}},
		{"KubernetesStart", func(ctx context.Context, c pb.ColimaServiceClient, p string) error {
			_, err := c.KubernetesStart(ctx, &pb.ProfileRequest{Profile: p})
			return err
		}},
		{"KubernetesStop", func(ctx context.Context, c pb.ColimaServiceClient, p string) error {
			_, err := c.KubernetesStop(ctx, &pb.ProfileRequest{Profile: p})
			return err
		}},
		{"KubernetesReset", func(ctx context.Context, c pb.ColimaServiceClient, p string) error {
			_, err := c.KubernetesReset(ctx, &pb.ProfileRequest{Profile: p})
			return err
		}},
		{"KillProcess", func(ctx context.Context, c pb.ColimaServiceClient, p string) error {
			_, err := c.KillProcess(ctx, &pb.KillProcessRequest{Profile: p, Pid: 1})
			return err
		}},
		{"UpdateRuntime", func(ctx context.Context, c pb.ColimaServiceClient, p string) error {
			_, err := c.UpdateRuntime(ctx, &pb.ProfileRequest{Profile: p})
			return err
		}},
		{"SwitchRuntime", func(ctx context.Context, c pb.ColimaServiceClient, p string) error {
			_, err := c.SwitchRuntime(ctx, &pb.SwitchRuntimeRequest{Profile: p, Runtime: "docker"})
			return err
		}},
		{"ModelServe", func(ctx context.Context, c pb.ColimaServiceClient, p string) error {
			_, err := c.ModelServe(ctx, &pb.ModelServeRequest{Profile: p})
			return err
		}},
		{"ModelStop", func(ctx context.Context, c pb.ColimaServiceClient, p string) error {
			_, err := c.ModelStop(ctx, &pb.ProfileRequest{Profile: p})
			return err
		}},
		{"CreateProfile", func(ctx context.Context, c pb.ColimaServiceClient, p string) error {
			_, err := c.CreateProfile(ctx, &pb.CreateProfileRequest{Name: p})
			return err
		}},
		{"DeleteProfile", func(ctx context.Context, c pb.ColimaServiceClient, p string) error {
			_, err := c.DeleteProfile(ctx, &pb.DeleteProfileRequest{Name: p})
			return err
		}},
		{"CloneProfile", func(ctx context.Context, c pb.ColimaServiceClient, p string) error {
			_, err := c.CloneProfile(ctx, &pb.CloneProfileRequest{Source: p, Destination: "dst"})
			return err
		}},
		{"SetConfig", func(ctx context.Context, c pb.ColimaServiceClient, p string) error {
			_, err := c.SetConfig(ctx, &pb.SetConfigRequest{Profile: p, Config: &pb.ColimaConfig{}})
			return err
		}},
	}

	ctx := context.Background()
	for i := 0; i < propIters; i++ {
		inv := invokers[i%len(invokers)]
		p := randOmittedProfile(rng)

		err := inv.call(ctx, client, p)
		assertContextualInvalidArgument(t, "Property 11 "+inv.name+" omitted profile "+quote(p), err, "required")

		select {
		case c := <-cmdCalls:
			t.Fatalf("Property 11 counterexample (seed=%d iter=%d rpc=%s profile=%q): executed command %s %#v despite unscoped request", seed, i, inv.name, p, c.name, c.args)
		default:
		}
		select {
		case c := <-lineCalls:
			t.Fatalf("Property 11 counterexample (seed=%d iter=%d rpc=%s profile=%q): executed streamed command %s %#v despite unscoped request", seed, i, inv.name, p, c.name, c.args)
		default:
		}
	}
}

// TestProperty11_MutatingColimaStreamsRejectOmittedProfile drives the mutating
// streaming ColimaService RPCs with an omitted profile and asserts the first
// Recv yields a contextual InvalidArgument and no command is executed.
//
// Feature: cross-platform-live-verification, Property 11
func TestProperty11_MutatingColimaStreamsRejectOmittedProfile(t *testing.T) {
	const seed = int64(0x11f)
	rng := rand.New(rand.NewSource(seed))

	cmdCalls := make(chan commandCall, 8)
	lineCalls := make(chan commandCall, 8)
	impl := New()
	impl.commandRunner = recordingRunner(cmdCalls, []byte("ok"), nil)
	impl.lineCommandRunner = func(_ context.Context, name string, args []string, onLine func(string) error) error {
		lineCalls <- commandCall{name: name, args: append([]string(nil), args...)}
		return onLine("line")
	}
	client := newTestClient(t, impl)

	invokers := []struct {
		name string
		call func(ctx context.Context, c pb.ColimaServiceClient, profile string) error
	}{
		{"Start", func(ctx context.Context, c pb.ColimaServiceClient, p string) error {
			s, err := c.Start(ctx, &pb.StartRequest{Profile: p})
			if err != nil {
				return err
			}
			_, err = s.Recv()
			return err
		}},
		{"Restart", func(ctx context.Context, c pb.ColimaServiceClient, p string) error {
			s, err := c.Restart(ctx, &pb.RestartRequest{Profile: p})
			if err != nil {
				return err
			}
			_, err = s.Recv()
			return err
		}},
		{"ModelSetup", func(ctx context.Context, c pb.ColimaServiceClient, p string) error {
			s, err := c.ModelSetup(ctx, &pb.ModelRequest{Profile: p})
			if err != nil {
				return err
			}
			_, err = s.Recv()
			return err
		}},
		{"ModelRun", func(ctx context.Context, c pb.ColimaServiceClient, p string) error {
			s, err := c.ModelRun(ctx, &pb.ModelRunRequest{Profile: p, Model: "ai/test"})
			if err != nil {
				return err
			}
			_, err = s.Recv()
			return err
		}},
	}

	ctx := context.Background()
	for i := 0; i < propIters; i++ {
		inv := invokers[i%len(invokers)]
		p := randOmittedProfile(rng)

		err := inv.call(ctx, client, p)
		assertContextualInvalidArgument(t, "Property 11 stream "+inv.name+" omitted profile "+quote(p), err, "required")

		select {
		case c := <-cmdCalls:
			t.Fatalf("Property 11 counterexample (seed=%d iter=%d rpc=%s profile=%q): executed command %s %#v despite unscoped stream request", seed, i, inv.name, p, c.name, c.args)
		default:
		}
		select {
		case c := <-lineCalls:
			t.Fatalf("Property 11 counterexample (seed=%d iter=%d rpc=%s profile=%q): executed streamed command %s %#v despite unscoped stream request", seed, i, inv.name, p, c.name, c.args)
		default:
		}
	}
}

// TestProperty11_MutatingDockerRPCsRejectOmittedScope drives the mutating
// DockerService unary RPCs with an omitted scope (no profile, no WSL2) and
// asserts each returns the contextual "not safely scoped" error — proving
// rejection at the guard before any docker.New/HTTP call is made.
//
// Feature: cross-platform-live-verification, Property 11
func TestProperty11_MutatingDockerRPCsRejectOmittedScope(t *testing.T) {
	const seed = int64(0x120)
	rng := rand.New(rand.NewSource(seed))
	client := newDockerClient(t)
	invokers := dockerMutationInvokers()

	ctx := context.Background()
	for i := 0; i < propIters; i++ {
		inv := invokers[i%len(invokers)]
		p := randOmittedProfile(rng)
		host := randHost(rng)

		errStr, transportErr := inv.call(ctx, client, p, host, false)
		if transportErr != nil {
			t.Fatalf("Property 11 counterexample (seed=%d iter=%d rpc=%s profile=%q host=%q): unexpected transport error: %v", seed, i, inv.name, p, host, transportErr)
		}
		if !strings.Contains(errStr, "not safely scoped") {
			t.Fatalf("Property 11 counterexample (seed=%d iter=%d rpc=%s profile=%q host=%q): response error = %q, want the contextual scope-rejection (proves no docker call was made)", seed, i, inv.name, p, host, errStr)
		}
	}
}

// TestProperty11_WSL2OnlyDockerScopeIsPermitted asserts a mutating docker
// request scoped by the WSL2 provider alone (no profile) passes the scope guard
// (it is NOT rejected with the "not safely scoped" error).
//
// Feature: cross-platform-live-verification, Property 11
func TestProperty11_WSL2OnlyDockerScopeIsPermitted(t *testing.T) {
	const seed = int64(0x121)
	rng := rand.New(rand.NewSource(seed))
	client := newDockerClient(t)
	invokers := dockerMutationInvokers()

	ctx := context.Background()
	for i := 0; i < propIters; i++ {
		inv := invokers[i%len(invokers)]
		p := randOmittedProfile(rng) // no profile — WSL2 provides the scope.

		errStr, transportErr := inv.call(ctx, client, p, "", true)
		if transportErr != nil {
			t.Fatalf("Property 11 counterexample (seed=%d iter=%d rpc=%s): unexpected transport error: %v", seed, i, inv.name, transportErr)
		}
		if strings.Contains(errStr, "not safely scoped") {
			t.Fatalf("Property 11 counterexample (seed=%d iter=%d rpc=%s): WSL2-only scope was rejected by the scope guard: %q", seed, i, inv.name, errStr)
		}
	}
}

// TestProperty11_ImageStreamsRejectOmittedScopeWithoutDockerCall asserts
// PullImage / PushImage with an omitted scope emit a terminal error event with
// the contextual scope-rejection AND never invoke the image-client factory
// (no docker call is made).
//
// Feature: cross-platform-live-verification, Property 11
func TestProperty11_ImageStreamsRejectOmittedScopeWithoutDockerCall(t *testing.T) {
	const seed = int64(0x122)
	rng := rand.New(rand.NewSource(seed))

	client, targets := newImageTargetServer(t)
	rpcs := imageRPCs()
	ops := []struct {
		name string
		fn   imageRPC
	}{
		{"pull", rpcs["pull"]},
		{"push", rpcs["push"]},
	}

	ctx := context.Background()
	for i := 0; i < propIters; i++ {
		op := ops[i%len(ops)]
		p := randOmittedProfile(rng)
		host := randHost(rng)

		stream, err := op.fn(client, ctx, &pb.NameRequest{Name: "alpine:latest", Profile: p, Host: host})
		if err != nil {
			t.Fatalf("Property 11 counterexample (seed=%d iter=%d op=%s profile=%q): start stream: %v", seed, i, op.name, p, err)
		}
		events := receiveProgress(t, stream)
		if len(events) == 0 {
			t.Fatalf("Property 11 counterexample (seed=%d iter=%d op=%s profile=%q): no terminal error event received", seed, i, op.name, p)
		}
		terminal := events[len(events)-1]
		if !terminal.Done || !strings.Contains(terminal.Error, "not safely scoped") {
			t.Fatalf("Property 11 counterexample (seed=%d iter=%d op=%s profile=%q): terminal event = %#v, want contextual scope-rejection", seed, i, op.name, p, terminal)
		}
		select {
		case tgt := <-targets:
			t.Fatalf("Property 11 counterexample (seed=%d iter=%d op=%s profile=%q): image-client factory invoked with %#v despite unscoped request — a docker call was made", seed, i, op.name, p, tgt)
		default:
		}
	}
}

// TestProperty11_ImageStreamsPermitWSL2OnlyScope asserts PullImage / PushImage
// scoped by the WSL2 provider alone pass the guard and reach the factory.
//
// Feature: cross-platform-live-verification, Property 11
func TestProperty11_ImageStreamsPermitWSL2OnlyScope(t *testing.T) {
	const seed = int64(0x123)
	rng := rand.New(rand.NewSource(seed))

	client, targets := newImageTargetServer(t)
	rpcs := imageRPCs()
	ops := []struct {
		name string
		fn   imageRPC
	}{
		{"pull", rpcs["pull"]},
		{"push", rpcs["push"]},
	}

	ctx := context.Background()
	for i := 0; i < propIters; i++ {
		op := ops[i%len(ops)]
		p := randOmittedProfile(rng) // WSL2 provides the scope.

		stream, err := op.fn(client, ctx, &pb.NameRequest{Name: "alpine:latest", Profile: p, Wsl2: true})
		if err != nil {
			t.Fatalf("Property 11 counterexample (seed=%d iter=%d op=%s): start stream: %v", seed, i, op.name, err)
		}
		_ = receiveProgress(t, stream)
		select {
		case tgt := <-targets:
			if !tgt.WSL2 {
				t.Fatalf("Property 11 counterexample (seed=%d iter=%d op=%s): forwarded target is not WSL2-scoped: %#v", seed, i, op.name, tgt)
			}
		default:
			t.Fatalf("Property 11 counterexample (seed=%d iter=%d op=%s): WSL2-only scope was rejected — factory never reached", seed, i, op.name)
		}
	}
}

// TestProperty11_ColimaReadRPCKeepsDefaultFallback asserts a read RPC (SSHConfig)
// with an omitted profile is NOT rejected and falls back to the default profile,
// while a present profile is honored — the documented read-side behavior.
//
// Feature: cross-platform-live-verification, Property 11
func TestProperty11_ColimaReadRPCKeepsDefaultFallback(t *testing.T) {
	const seed = int64(0x124)
	rng := rand.New(rand.NewSource(seed))

	calls := make(chan commandCall, 4)
	impl := New()
	impl.commandRunner = recordingRunner(calls, []byte("ssh-config-output"), nil)
	client := newTestClient(t, impl)

	ctx := context.Background()
	for i := 0; i < propIters; i++ {
		var p string
		if rng.Intn(2) == 0 {
			p = randOmittedProfile(rng)
		} else {
			p = randScopedProfile(rng)
		}

		if _, err := client.SSHConfig(ctx, &pb.ProfileRequest{Profile: p}); err != nil {
			t.Fatalf("Property 11 counterexample (seed=%d iter=%d profile=%q): read RPC SSHConfig was rejected instead of falling back: %v", seed, i, p, err)
		}
		call := receiveCall(t, calls)
		want := normalizedProfile(p) // omitted → "default"
		if call.name != "colima" || len(call.args) < 2 || call.args[0] != "--profile" || call.args[1] != want {
			t.Fatalf("Property 11 counterexample (seed=%d iter=%d profile=%q): SSHConfig built %s %#v, want leading `colima --profile %s` (default fallback)", seed, i, p, call.name, call.args, want)
		}
	}
}

// ─── shared docker-mutation invoker table & image server helper ─────────────

type dockerMutationInvoker struct {
	name string
	// call performs the mutating docker RPC and returns the response .Error
	// string (empty on success) plus any transport error.
	call func(ctx context.Context, c pb.DockerServiceClient, profile, host string, wsl2 bool) (string, error)
}

func dockerMutationInvokers() []dockerMutationInvoker {
	return []dockerMutationInvoker{
		{"ContainerAction", func(ctx context.Context, c pb.DockerServiceClient, p, h string, w bool) (string, error) {
			r, err := c.ContainerAction(ctx, &pb.ContainerActionRequest{Id: "x", Action: "start", Profile: p, Host: h, Wsl2: w})
			return errOf(err, func() string { return r.GetError() }), err
		}},
		{"CreateContainer", func(ctx context.Context, c pb.DockerServiceClient, p, h string, w bool) (string, error) {
			r, err := c.CreateContainer(ctx, &pb.CreateContainerRequest{Name: "n", Image: "img", Profile: p, Host: h, Wsl2: w})
			return errOf(err, func() string { return r.GetError() }), err
		}},
		{"RenameContainer", func(ctx context.Context, c pb.DockerServiceClient, p, h string, w bool) (string, error) {
			r, err := c.RenameContainer(ctx, &pb.RenameRequest{Id: "x", NewName: "y", Profile: p, Host: h, Wsl2: w})
			return errOf(err, func() string { return r.GetError() }), err
		}},
		{"PruneContainers", func(ctx context.Context, c pb.DockerServiceClient, p, h string, w bool) (string, error) {
			r, err := c.PruneContainers(ctx, &pb.DockerScope{Profile: p, Host: h, Wsl2: w})
			return errOf(err, func() string { return r.GetError() }), err
		}},
		{"RemoveImage", func(ctx context.Context, c pb.DockerServiceClient, p, h string, w bool) (string, error) {
			r, err := c.RemoveImage(ctx, &pb.IdRequest{Id: "x", Profile: p, Host: h, Wsl2: w})
			return errOf(err, func() string { return r.GetError() }), err
		}},
		{"TagImage", func(ctx context.Context, c pb.DockerServiceClient, p, h string, w bool) (string, error) {
			r, err := c.TagImage(ctx, &pb.TagRequest{Name: "n", Repo: "r", Tag: "t", Profile: p, Host: h, Wsl2: w})
			return errOf(err, func() string { return r.GetError() }), err
		}},
		{"PruneImages", func(ctx context.Context, c pb.DockerServiceClient, p, h string, w bool) (string, error) {
			r, err := c.PruneImages(ctx, &pb.DockerScope{Profile: p, Host: h, Wsl2: w})
			return errOf(err, func() string { return r.GetError() }), err
		}},
		{"CreateVolume", func(ctx context.Context, c pb.DockerServiceClient, p, h string, w bool) (string, error) {
			r, err := c.CreateVolume(ctx, &pb.NameRequest{Name: "v", Profile: p, Host: h, Wsl2: w})
			return errOf(err, func() string { return r.GetError() }), err
		}},
		{"RemoveVolume", func(ctx context.Context, c pb.DockerServiceClient, p, h string, w bool) (string, error) {
			r, err := c.RemoveVolume(ctx, &pb.NameRequest{Name: "v", Profile: p, Host: h, Wsl2: w})
			return errOf(err, func() string { return r.GetError() }), err
		}},
		{"PruneVolumes", func(ctx context.Context, c pb.DockerServiceClient, p, h string, w bool) (string, error) {
			r, err := c.PruneVolumes(ctx, &pb.DockerScope{Profile: p, Host: h, Wsl2: w})
			return errOf(err, func() string { return r.GetError() }), err
		}},
		{"CreateNetwork", func(ctx context.Context, c pb.DockerServiceClient, p, h string, w bool) (string, error) {
			r, err := c.CreateNetwork(ctx, &pb.NameRequest{Name: "net", Profile: p, Host: h, Wsl2: w})
			return errOf(err, func() string { return r.GetError() }), err
		}},
		{"RemoveNetwork", func(ctx context.Context, c pb.DockerServiceClient, p, h string, w bool) (string, error) {
			r, err := c.RemoveNetwork(ctx, &pb.IdRequest{Id: "x", Profile: p, Host: h, Wsl2: w})
			return errOf(err, func() string { return r.GetError() }), err
		}},
		{"ConnectNetwork", func(ctx context.Context, c pb.DockerServiceClient, p, h string, w bool) (string, error) {
			r, err := c.ConnectNetwork(ctx, &pb.NetworkContainerRequest{NetworkId: "n", ContainerId: "c", Profile: p, Host: h, Wsl2: w})
			return errOf(err, func() string { return r.GetError() }), err
		}},
		{"DisconnectNetwork", func(ctx context.Context, c pb.DockerServiceClient, p, h string, w bool) (string, error) {
			r, err := c.DisconnectNetwork(ctx, &pb.NetworkContainerRequest{NetworkId: "n", ContainerId: "c", Profile: p, Host: h, Wsl2: w})
			return errOf(err, func() string { return r.GetError() }), err
		}},
		{"PruneNetworks", func(ctx context.Context, c pb.DockerServiceClient, p, h string, w bool) (string, error) {
			r, err := c.PruneNetworks(ctx, &pb.DockerScope{Profile: p, Host: h, Wsl2: w})
			return errOf(err, func() string { return r.GetError() }), err
		}},
	}
}

// errOf returns the response error string only when there was no transport
// error (so a nil response is never dereferenced).
func errOf(transportErr error, get func() string) string {
	if transportErr != nil {
		return ""
	}
	return get()
}

// newImageTargetServer builds a DockerService whose image-client factory records
// every docker.Target it receives into the returned channel and streams a
// trivial success body. When the scope guard rejects a request the factory is
// never called, so the channel stays empty.
func newImageTargetServer(t *testing.T) (pb.DockerServiceClient, chan docker.Target) {
	t.Helper()
	targets := make(chan docker.Target, 8)
	server := NewDocker()
	server.imageClientFactory = func(target docker.Target) (imageClient, error) {
		targets <- target
		return &fakeImageClient{
			pull: func(context.Context, string) (io.ReadCloser, error) {
				return io.NopCloser(strings.NewReader(`{"status":"ok"}`)), nil
			},
			push: func(context.Context, string) (io.ReadCloser, error) {
				return io.NopCloser(strings.NewReader(`{"status":"ok"}`)), nil
			},
		}, nil
	}
	return newDockerClient(t, server), targets
}

// quote renders a possibly-whitespace profile string visibly in failure output.
func quote(s string) string { return "\"" + s + "\"" }
