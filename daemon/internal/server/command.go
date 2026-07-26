package server

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"os/exec"
	"strings"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

type commandRunner func(context.Context, string, ...string) ([]byte, error)

type lineCommandRunner func(context.Context, string, []string, func(string) error) error

type lineCallbackError struct {
	err error
}

func (err *lineCallbackError) Error() string { return err.err.Error() }
func (err *lineCallbackError) Unwrap() error { return err.err }

func defaultCommandRunner(ctx context.Context, name string, args ...string) ([]byte, error) {
	return exec.CommandContext(ctx, name, args...).CombinedOutput()
}

func defaultLineCommandRunner(ctx context.Context, name string, args []string, onLine func(string) error) error {
	command := exec.CommandContext(ctx, name, args...)
	stdout, err := command.StdoutPipe()
	if err != nil {
		return err
	}
	command.Stderr = command.Stdout
	if err := command.Start(); err != nil {
		return err
	}

	scanner := bufio.NewScanner(stdout)
	scanner.Buffer(make([]byte, 0, 64*1024), 4*1024*1024)
	for scanner.Scan() {
		if err := onLine(scanner.Text()); err != nil {
			_ = command.Process.Kill()
			_ = command.Wait()
			return &lineCallbackError{err: err}
		}
	}
	if err := scanner.Err(); err != nil {
		_ = command.Process.Kill()
		_ = command.Wait()
		return err
	}
	if err := command.Wait(); err != nil {
		if ctxErr := ctx.Err(); ctxErr != nil {
			return ctxErr
		}
		return err
	}
	return nil
}

func (s *ColimaServer) execute(ctx context.Context, name string, args ...string) ([]byte, error) {
	runner := s.commandRunner
	if runner == nil {
		runner = defaultCommandRunner
	}
	return runner(ctx, name, args...)
}

func (s *ColimaServer) executeLines(ctx context.Context, name string, args []string, onLine func(string) error) error {
	runner := s.lineCommandRunner
	if runner == nil {
		runner = defaultLineCommandRunner
	}
	return runner(ctx, name, args, onLine)
}

func commandFailure(name string, args []string, output []byte, err error) error {
	detail := strings.TrimSpace(string(output))
	command := strings.TrimSpace(name + " " + strings.Join(args, " "))
	if detail == "" {
		return fmt.Errorf("%s: %w", command, err)
	}
	return fmt.Errorf("%s: %w: %s", command, err, detail)
}

func statusFromCommand(name string, args []string, output []byte, err error) *statusResult {
	if err != nil {
		return &statusResult{err: commandFailure(name, args, output, err)}
	}
	return &statusResult{message: strings.TrimSpace(string(output))}
}

type statusResult struct {
	message string
	err     error
}

func normalizedProfile(profile string) string {
	profile = strings.TrimSpace(profile)
	if profile == "" || profile == "colima" {
		return "default"
	}
	return strings.TrimPrefix(profile, "colima-")
}

func colimaProfileArgs(profile string, args ...string) []string {
	result := []string{"--profile", normalizedProfile(profile)}
	return append(result, args...)
}

// Scope validation (Requirement 3.4/3.5; design Property 10 & 11).
//
// normalizedProfile maps an empty profile to "default" so that a caller who
// *explicitly* asks for the default profile is served. That convenience is
// exactly what makes an *omitted* profile dangerous: a mutating request that
// forgot to carry its scope would silently target the implicit default profile
// (or the default Docker socket) instead of being rejected. The guards below
// reject that case with a contextual error before any command is constructed,
// so a profile-scoped mutation never runs against global/default state by
// accident. Read-only handlers intentionally keep the empty→default fallback.

// requireProfile rejects a profile-scoped mutating request that omits its
// profile. It does NOT reject an explicit "default"/"colima" profile — only a
// blank/whitespace one, which would otherwise normalize to the default profile.
func requireProfile(profile string) error {
	if strings.TrimSpace(profile) == "" {
		return status.Error(codes.InvalidArgument,
			"profile is required: refusing to run a profile-scoped command against the implicit default profile")
	}
	return nil
}

// requireScopeField rejects a request that omits a named scope field required
// for safe targeting (e.g. the profile name to create/delete, or a clone
// source/destination). field names the offending argument for the caller.
func requireScopeField(value, field string) error {
	if strings.TrimSpace(value) == "" {
		return status.Errorf(codes.InvalidArgument,
			"%s is required: refusing to run an unscoped profile operation", field)
	}
	return nil
}

// requireDockerScope rejects a mutating Docker request that selects neither a
// profile nor the WSL2 provider. Without a profile (and outside WSL2) the
// client falls back to the default profile's docker.sock, silently mutating
// whatever engine answers there. A WSL2 request is explicitly scoped to the
// Windows Docker engine and needs no profile; a remote SSH host still resolves
// its socket under a profile directory, so host alone does not relax the rule.
func requireDockerScope(profile string, wsl2 bool) error {
	if wsl2 {
		return nil
	}
	if strings.TrimSpace(profile) == "" {
		return status.Error(codes.InvalidArgument,
			"docker request is not safely scoped: set a profile or the WSL2 provider before targeting the engine")
	}
	return nil
}

func kubeContextForProfile(profile string) string {
	profile = normalizedProfile(profile)
	if profile == "default" {
		return "colima"
	}
	return "colima-" + profile
}

func asLineCallbackError(err error) error {
	var callbackErr *lineCallbackError
	if errors.As(err, &callbackErr) {
		return callbackErr.err
	}
	return nil
}
