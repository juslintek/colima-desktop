// Package docker is the daemon's Docker Engine API client. It talks HTTP over
// the colima unix socket (local), a remote host's socket (SSH), or a Windows
// WSL2/Docker engine. Responses are raw Docker API JSON (JSON-passthrough).
package docker

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"
)

const requestTimeout = 30 * time.Second

// Target selects which backend to reach.
type Target struct {
	Profile string
	Host    string // "user@host" for remote SSH; empty = local
	WSL2    bool   // Windows: use local WSL2/Docker engine
}

func (t Target) profile() string {
	if t.Profile == "" {
		return "default"
	}
	return t.Profile
}

// SocketPath returns the local colima docker socket for the profile.
func (t Target) SocketPath() string {
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".colima", t.profile(), "docker.sock")
}

// Client is a minimal Docker Engine API client bound to a Target.
type Client struct {
	hc      *http.Client
	apiBase string // "http://docker" — host is ignored for unix/ssh transports
}

// New builds a client for the given target (local, remote-SSH, or WSL2).
func New(t Target) (*Client, error) {
	tr, base, err := transportFor(t)
	if err != nil {
		return nil, err
	}
	// Streaming image operations can legitimately take longer than a fixed HTTP
	// client timeout. Unary calls apply requestTimeout in do instead, while
	// streams are bounded by their caller's context.
	return &Client{hc: &http.Client{Transport: tr}, apiBase: base}, nil
}

// CloseIdleConnections releases provider connections retained by the HTTP
// transport after a request completes. Streaming RPC handlers call this when
// their per-request client is no longer needed.
func (c *Client) CloseIdleConnections() {
	c.hc.CloseIdleConnections()
}

// localTransport dials the local unix socket.
func localTransport(sock string) *http.Transport {
	return &http.Transport{
		DialContext: func(ctx context.Context, _, _ string) (net.Conn, error) {
			return (&net.Dialer{}).DialContext(ctx, "unix", sock)
		},
	}
}

// --- HTTP helpers ---

func (c *Client) request(ctx context.Context, method, path string, body []byte, headers http.Header) (*http.Response, error) {
	var r io.Reader
	if body != nil {
		r = bytes.NewReader(body)
	}
	req, err := http.NewRequestWithContext(ctx, method, c.apiBase+path, r)
	if err != nil {
		return nil, fmt.Errorf("create docker api request: %w", err)
	}
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	for key, values := range headers {
		for _, value := range values {
			req.Header.Add(key, value)
		}
	}
	resp, err := c.hc.Do(req)
	if err != nil {
		return nil, fmt.Errorf("docker api %s %s: %w", method, path, err)
	}
	if resp.StatusCode >= 400 {
		defer resp.Body.Close()
		out, readErr := io.ReadAll(io.LimitReader(resp.Body, 1024*1024))
		if readErr != nil {
			return nil, fmt.Errorf("docker api %s %s returned %s (read error: %v)", method, path, resp.Status, readErr)
		}
		detail := strings.TrimSpace(string(out))
		if detail == "" {
			return nil, fmt.Errorf("docker api %s %s returned %s", method, path, resp.Status)
		}
		return nil, fmt.Errorf("docker api %s %s returned %s: %s", method, path, resp.Status, detail)
	}
	return resp, nil
}

func (c *Client) do(method, path string, body []byte) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), requestTimeout)
	defer cancel()
	resp, err := c.request(ctx, method, path, body, nil)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	out, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("read docker api %s %s response: %w", method, path, err)
	}
	return string(out), nil
}

func (c *Client) get(path string) (string, error)            { return c.do(http.MethodGet, path, nil) }
func (c *Client) post(path string, b []byte) (string, error) { return c.do(http.MethodPost, path, b) }
func (c *Client) del(path string) (string, error)            { return c.do(http.MethodDelete, path, nil) }

// --- Containers ---

func (c *Client) ListContainers(all bool) (string, error) {
	q := ""
	if all {
		q = "?all=1"
	}
	return c.get("/containers/json" + q)
}
func (c *Client) ContainerAction(id, action string) error {
	var err error
	switch action {
	case "remove":
		_, err = c.del("/containers/" + id + "?force=1")
	case "start", "stop", "kill", "restart", "pause", "unpause":
		_, err = c.post("/containers/"+id+"/"+action, nil)
	default:
		err = fmt.Errorf("unknown container action %q", action)
	}
	return err
}
func (c *Client) CreateContainer(name, image string) (string, error) {
	body := []byte(fmt.Sprintf(`{"Image":%q}`, image))
	p := "/containers/create"
	if name != "" {
		p += "?name=" + name
	}
	return c.post(p, body)
}
func (c *Client) RenameContainer(id, newName string) error {
	_, err := c.post("/containers/"+id+"/rename?name="+newName, nil)
	return err
}
func (c *Client) ContainerLogs(id string) (string, error) {
	return c.get("/containers/" + id + "/logs?stdout=1&stderr=1&tail=1000")
}
func (c *Client) InspectContainer(id string) (string, error) {
	return c.get("/containers/" + id + "/json")
}
func (c *Client) ContainerTop(id string) (string, error) { return c.get("/containers/" + id + "/top") }
func (c *Client) ContainerStats(id string) (string, error) {
	return c.get("/containers/" + id + "/stats?stream=0")
}
func (c *Client) ContainerChanges(id string) (string, error) {
	return c.get("/containers/" + id + "/changes")
}
func (c *Client) PruneContainers() (string, error) { return c.post("/containers/prune", nil) }

// --- Images ---

func (c *Client) ListImages() (string, error) { return c.get("/images/json") }
func (c *Client) RemoveImage(id string) error {
	_, err := c.del("/images/" + id + "?force=1")
	return err
}
func (c *Client) InspectImage(name string) (string, error) { return c.get("/images/" + name + "/json") }
func (c *Client) ImageHistory(name string) (string, error) {
	return c.get("/images/" + name + "/history")
}
func (c *Client) TagImage(name, repo, tag string) error {
	_, err := c.post("/images/"+name+"/tag?repo="+repo+"&tag="+tag, nil)
	return err
}
func (c *Client) SearchImages(term string) (string, error) {
	return c.get("/images/search?term=" + term)
}
func (c *Client) PruneImages() (string, error) { return c.post("/images/prune", nil) }

// PullImage starts a Docker Engine image-pull request and returns its JSON
// progress stream. The caller owns the response body and must close it.
func (c *Client) PullImage(ctx context.Context, name string) (io.ReadCloser, error) {
	if strings.TrimSpace(name) == "" {
		return nil, fmt.Errorf("image name is required")
	}
	query := url.Values{"fromImage": []string{name}}
	resp, err := c.request(ctx, http.MethodPost, "/images/create?"+query.Encode(), nil, nil)
	if err != nil {
		return nil, err
	}
	return resp.Body, nil
}

// PushImage starts a Docker Engine image-push request and returns its JSON
// progress stream. The frozen NameRequest contract does not carry registry
// credentials, so an empty auth object requests the daemon's configured or
// anonymous registry credentials.
func (c *Client) PushImage(ctx context.Context, name string) (io.ReadCloser, error) {
	if strings.TrimSpace(name) == "" {
		return nil, fmt.Errorf("image name is required")
	}
	headers := http.Header{"X-Registry-Auth": []string{"e30="}} // base64("{}")
	resp, err := c.request(ctx, http.MethodPost, "/images/"+url.PathEscape(name)+"/push", nil, headers)
	if err != nil {
		return nil, err
	}
	return resp.Body, nil
}

// --- Volumes ---

func (c *Client) ListVolumes() (string, error) { return c.get("/volumes") }
func (c *Client) CreateVolume(name string) (string, error) {
	return c.post("/volumes/create", []byte(fmt.Sprintf(`{"Name":%q}`, name)))
}
func (c *Client) RemoveVolume(name string) error            { _, err := c.del("/volumes/" + name); return err }
func (c *Client) InspectVolume(name string) (string, error) { return c.get("/volumes/" + name) }
func (c *Client) PruneVolumes() (string, error)             { return c.post("/volumes/prune", nil) }

// --- Networks ---

func (c *Client) ListNetworks() (string, error) { return c.get("/networks") }
func (c *Client) CreateNetwork(name string) (string, error) {
	return c.post("/networks/create", []byte(fmt.Sprintf(`{"Name":%q}`, name)))
}
func (c *Client) RemoveNetwork(id string) error            { _, err := c.del("/networks/" + id); return err }
func (c *Client) InspectNetwork(id string) (string, error) { return c.get("/networks/" + id) }
func (c *Client) ConnectNetwork(netID, containerID string) error {
	_, err := c.post("/networks/"+netID+"/connect", []byte(fmt.Sprintf(`{"Container":%q}`, containerID)))
	return err
}
func (c *Client) DisconnectNetwork(netID, containerID string) error {
	_, err := c.post("/networks/"+netID+"/disconnect", []byte(fmt.Sprintf(`{"Container":%q}`, containerID)))
	return err
}
func (c *Client) PruneNetworks() (string, error) { return c.post("/networks/prune", nil) }

// StreamPath returns a streaming response body reader for events/logs/stats.
func (c *Client) StreamPath(path string) (io.ReadCloser, error) {
	resp, err := c.request(context.Background(), http.MethodGet, path, nil, nil)
	if err != nil {
		return nil, err
	}
	return resp.Body, nil
}
