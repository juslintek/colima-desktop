package docker

import (
	"context"
	"errors"
	"io"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

type roundTripFunc func(*http.Request) (*http.Response, error)

func (f roundTripFunc) RoundTrip(request *http.Request) (*http.Response, error) {
	return f(request)
}

type trackingBody struct {
	io.Reader
	closed atomic.Bool
}

func (b *trackingBody) Close() error {
	b.closed.Store(true)
	return nil
}

func TestImageStreamRequests(t *testing.T) {
	tests := []struct {
		name             string
		image            string
		wantRequestURI   string
		wantRegistryAuth string
		open             func(*Client, context.Context, string) (io.ReadCloser, error)
	}{
		{
			name:           "pull",
			image:          "registry.example/team/image:latest",
			wantRequestURI: "/images/create?fromImage=registry.example%2Fteam%2Fimage%3Alatest",
			open:           (*Client).PullImage,
		},
		{
			name:             "push",
			image:            "registry.example/team/image:latest",
			wantRequestURI:   "/images/registry.example%2Fteam%2Fimage:latest/push",
			wantRegistryAuth: "e30=",
			open:             (*Client).PushImage,
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			responseBody := &trackingBody{Reader: strings.NewReader("{\"status\":\"ok\"}\n")}
			client := &Client{
				apiBase: "http://docker",
				hc: &http.Client{Transport: roundTripFunc(func(request *http.Request) (*http.Response, error) {
					if request.Method != http.MethodPost {
						t.Errorf("method = %q, want POST", request.Method)
					}
					if request.URL.RequestURI() != test.wantRequestURI {
						t.Errorf("request URI = %q, want %q", request.URL.RequestURI(), test.wantRequestURI)
					}
					if got := request.Header.Get("X-Registry-Auth"); got != test.wantRegistryAuth {
						t.Errorf("X-Registry-Auth = %q, want %q", got, test.wantRegistryAuth)
					}
					return &http.Response{
						StatusCode: http.StatusOK,
						Status:     "200 OK",
						Body:       responseBody,
						Header:     make(http.Header),
						Request:    request,
					}, nil
				})},
			}

			body, err := test.open(client, context.Background(), test.image)
			if err != nil {
				t.Fatalf("open stream: %v", err)
			}
			got, err := io.ReadAll(body)
			if err != nil {
				t.Fatalf("read stream: %v", err)
			}
			if string(got) != "{\"status\":\"ok\"}\n" {
				t.Fatalf("body = %q", got)
			}
			if err := body.Close(); err != nil {
				t.Fatalf("close stream: %v", err)
			}
			if !responseBody.closed.Load() {
				t.Fatal("response body was not closed")
			}
		})
	}
}

// imageStreamOpeners returns the client-level stream entry points keyed by
// operation so pull and push share identical error/cancellation assertions —
// PushImage is a distinct method (real POST /images/{name}/push with an
// X-Registry-Auth header), so it must be proven, not assumed via PullImage.
func imageStreamOpeners() []struct {
	name string
	open func(*Client, context.Context, string) (io.ReadCloser, error)
} {
	return []struct {
		name string
		open func(*Client, context.Context, string) (io.ReadCloser, error)
	}{
		{name: "pull", open: (*Client).PullImage},
		{name: "push", open: (*Client).PushImage},
	}
}

func TestImageStreamHTTPErrorIncludesBodyAndClosesIt(t *testing.T) {
	// A registry auth failure (401 with a daemon detail) must surface as an
	// error carrying the status + detail, and the error body must be closed —
	// verified for both pull and push at the client boundary.
	for _, operation := range imageStreamOpeners() {
		t.Run(operation.name, func(t *testing.T) {
			responseBody := &trackingBody{Reader: strings.NewReader(`{"message":"denied"}`)}
			client := &Client{
				apiBase: "http://docker",
				hc: &http.Client{Transport: roundTripFunc(func(request *http.Request) (*http.Response, error) {
					return &http.Response{
						StatusCode: http.StatusUnauthorized,
						Status:     "401 Unauthorized",
						Body:       responseBody,
						Header:     make(http.Header),
						Request:    request,
					}, nil
				})},
			}

			body, err := operation.open(client, context.Background(), "private/image:latest")
			if body != nil {
				t.Fatal("error response unexpectedly returned a body")
			}
			if err == nil || !strings.Contains(err.Error(), "401 Unauthorized") || !strings.Contains(err.Error(), "denied") {
				t.Fatalf("error = %v, want HTTP status and daemon detail", err)
			}
			if !responseBody.closed.Load() {
				t.Fatal("HTTP error response body was not closed")
			}
		})
	}
}

func TestImageStreamRequestUsesCallerContext(t *testing.T) {
	// Cancelling the caller context must abort the request (no body, raw
	// context.Canceled) for both pull and push.
	for _, operation := range imageStreamOpeners() {
		t.Run(operation.name, func(t *testing.T) {
			client := &Client{
				apiBase: "http://docker",
				hc: &http.Client{Transport: roundTripFunc(func(request *http.Request) (*http.Response, error) {
					<-request.Context().Done()
					return nil, request.Context().Err()
				})},
			}
			ctx, cancel := context.WithCancel(context.Background())
			cancel()

			body, err := operation.open(client, ctx, "alpine:latest")
			if body != nil {
				t.Fatal("cancelled request unexpectedly returned a body")
			}
			if !errors.Is(err, context.Canceled) {
				t.Fatalf("error = %v, want context.Canceled", err)
			}
		})
	}
}

func TestPullImageOverLocalUnixSocket(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("Unix sockets are not available on native Windows")
	}
	tempDir, err := os.MkdirTemp("/tmp", "colima-daemon-")
	if err != nil {
		t.Fatalf("create temp dir: %v", err)
	}
	t.Cleanup(func() { _ = os.RemoveAll(tempDir) })
	socketPath := filepath.Join(tempDir, "docker.sock")
	listener, err := net.Listen("unix", socketPath)
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	server := &http.Server{Handler: http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		if request.Method != http.MethodPost || request.URL.Path != "/images/create" {
			t.Errorf("request = %s %s", request.Method, request.URL.RequestURI())
		}
		_, _ = io.WriteString(writer, "{\"status\":\"downloaded\"}\n")
	})}
	serveDone := make(chan error, 1)
	go func() { serveDone <- server.Serve(listener) }()
	t.Cleanup(func() {
		ctx, cancel := context.WithTimeout(context.Background(), time.Second)
		defer cancel()
		_ = server.Shutdown(ctx)
		<-serveDone
	})

	client := &Client{
		apiBase: "http://docker",
		hc:      &http.Client{Transport: localTransport(socketPath)},
	}
	body, err := client.PullImage(context.Background(), "alpine:latest")
	if err != nil {
		t.Fatalf("pull over unix socket: %v", err)
	}
	defer body.Close()
	got, err := io.ReadAll(body)
	if err != nil {
		t.Fatalf("read: %v", err)
	}
	if string(got) != "{\"status\":\"downloaded\"}\n" {
		t.Fatalf("body = %q", got)
	}
}
