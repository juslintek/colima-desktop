package docker

import (
	"context"
	"fmt"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strings"

	"golang.org/x/crypto/ssh"
	"golang.org/x/crypto/ssh/agent"
)

// transportFor builds the right RoundTripper for the target and returns the
// API base URL (host is ignored by the unix/ssh transports).
func transportFor(t Target) (http.RoundTripper, string, error) {
	if t.WSL2 {
		return wsl2Transport(t) // build-tagged: real on Windows, error elsewhere
	}
	if t.Host != "" {
		tr, err := sshTransport(t)
		return tr, "http://docker", err
	}
	return localTransport(t.SocketPath()), "http://docker", nil
}

// sshTransport tunnels the Docker socket over SSH (remote colima/Lima host).
// Auth via SSH agent; remote socket assumed at ~/.colima/<profile>/docker.sock.
func sshTransport(t Target) (*http.Transport, error) {
	user, host := "", t.Host
	if i := strings.IndexByte(t.Host, '@'); i >= 0 {
		user, host = t.Host[:i], t.Host[i+1:]
	}
	if user == "" {
		user = os.Getenv("USER")
	}
	if !strings.Contains(host, ":") {
		host += ":22"
	}
	authSock := os.Getenv("SSH_AUTH_SOCK")
	if authSock == "" {
		return nil, fmt.Errorf("remote-ssh requires SSH_AUTH_SOCK (ssh-agent)")
	}
	agentConn, err := net.Dial("unix", authSock)
	if err != nil {
		return nil, fmt.Errorf("ssh-agent: %w", err)
	}
	signers := agent.NewClient(agentConn).Signers
	cfg := &ssh.ClientConfig{
		User:            user,
		Auth:            []ssh.AuthMethod{ssh.PublicKeysCallback(signers)},
		HostKeyCallback: ssh.InsecureIgnoreHostKey(), // remote hosts are user-configured
	}
	remoteSock := "/home/" + user + "/.colima/" + t.profile() + "/docker.sock"
	return &http.Transport{
		DialContext: func(ctx context.Context, _, _ string) (net.Conn, error) {
			client, err := ssh.Dial("tcp", host, cfg)
			if err != nil {
				return nil, err
			}
			return client.Dial("unix", remoteSock)
		},
	}, nil
}

var _ = filepath.Join // keep import stable across build tags
