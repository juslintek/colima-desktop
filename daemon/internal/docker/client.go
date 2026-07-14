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
	"os"
	"path/filepath"
	"time"
)

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
	return &Client{hc: &http.Client{Transport: tr, Timeout: 30 * time.Second}, apiBase: base}, nil
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

func (c *Client) do(method, path string, body []byte) (string, error) {
	var r io.Reader
	if body != nil {
		r = bytes.NewReader(body)
	}
	req, err := http.NewRequest(method, c.apiBase+path, r)
	if err != nil {
		return "", err
	}
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	resp, err := c.hc.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	out, _ := io.ReadAll(resp.Body)
	if resp.StatusCode >= 400 {
		return "", fmt.Errorf("docker api %d: %s", resp.StatusCode, string(out))
	}
	return string(out), nil
}

func (c *Client) get(path string) (string, error)          { return c.do(http.MethodGet, path, nil) }
func (c *Client) post(path string, b []byte) (string, error) { return c.do(http.MethodPost, path, b) }
func (c *Client) del(path string) (string, error)          { return c.do(http.MethodDelete, path, nil) }

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
func (c *Client) InspectContainer(id string) (string, error) { return c.get("/containers/" + id + "/json") }
func (c *Client) ContainerTop(id string) (string, error)     { return c.get("/containers/" + id + "/top") }
func (c *Client) ContainerStats(id string) (string, error) {
	return c.get("/containers/" + id + "/stats?stream=0")
}
func (c *Client) ContainerChanges(id string) (string, error) { return c.get("/containers/" + id + "/changes") }
func (c *Client) PruneContainers() (string, error)           { return c.post("/containers/prune", nil) }

// --- Images ---

func (c *Client) ListImages() (string, error)          { return c.get("/images/json") }
func (c *Client) RemoveImage(id string) error          { _, err := c.del("/images/" + id + "?force=1"); return err }
func (c *Client) InspectImage(name string) (string, error) { return c.get("/images/" + name + "/json") }
func (c *Client) ImageHistory(name string) (string, error) { return c.get("/images/" + name + "/history") }
func (c *Client) TagImage(name, repo, tag string) error {
	_, err := c.post("/images/"+name+"/tag?repo="+repo+"&tag="+tag, nil)
	return err
}
func (c *Client) SearchImages(term string) (string, error) { return c.get("/images/search?term=" + term) }
func (c *Client) PruneImages() (string, error)             { return c.post("/images/prune", nil) }
func (c *Client) PullImage(name string) (string, error)    { return c.post("/images/create?fromImage="+name, nil) }
func (c *Client) PushImage(name string) (string, error)    { return c.post("/images/"+name+"/push", nil) }

// --- Volumes ---

func (c *Client) ListVolumes() (string, error) { return c.get("/volumes") }
func (c *Client) CreateVolume(name string) (string, error) {
	return c.post("/volumes/create", []byte(fmt.Sprintf(`{"Name":%q}`, name)))
}
func (c *Client) RemoveVolume(name string) error       { _, err := c.del("/volumes/" + name); return err }
func (c *Client) InspectVolume(name string) (string, error) { return c.get("/volumes/" + name) }
func (c *Client) PruneVolumes() (string, error)        { return c.post("/volumes/prune", nil) }

// --- Networks ---

func (c *Client) ListNetworks() (string, error) { return c.get("/networks") }
func (c *Client) CreateNetwork(name string) (string, error) {
	return c.post("/networks/create", []byte(fmt.Sprintf(`{"Name":%q}`, name)))
}
func (c *Client) RemoveNetwork(id string) error        { _, err := c.del("/networks/" + id); return err }
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
	req, err := http.NewRequest(http.MethodGet, c.apiBase+path, nil)
	if err != nil {
		return nil, err
	}
	resp, err := c.hc.Do(req)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode >= 400 {
		resp.Body.Close()
		return nil, fmt.Errorf("docker api %d", resp.StatusCode)
	}
	return resp.Body, nil
}
