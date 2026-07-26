package docker

import (
	"context"
	"fmt"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"

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
	signers, err := agent.NewClient(agentConn).Signers()
	_ = agentConn.Close()
	if err != nil {
		return nil, fmt.Errorf("ssh-agent signers: %w", err)
	}
	if len(signers) == 0 {
		return nil, fmt.Errorf("remote-ssh requires at least one key in ssh-agent")
	}
	cfg := &ssh.ClientConfig{
		User:            user,
		Auth:            []ssh.AuthMethod{ssh.PublicKeys(signers...)},
		HostKeyCallback: ssh.InsecureIgnoreHostKey(), // remote hosts are user-configured
	}
	remoteSock := "/home/" + user + "/.colima/" + t.profile() + "/docker.sock"
	return &http.Transport{
		DialContext: func(ctx context.Context, _, _ string) (net.Conn, error) {
			rawConn, err := (&net.Dialer{}).DialContext(ctx, "tcp", host)
			if err != nil {
				return nil, fmt.Errorf("ssh connect %s: %w", host, err)
			}

			// ssh.NewClientConn has no context parameter. Closing the TCP
			// connection on cancellation makes its handshake cancellation-safe.
			stopHandshakeWatch := make(chan struct{})
			go func() {
				select {
				case <-ctx.Done():
					_ = rawConn.Close()
				case <-stopHandshakeWatch:
				}
			}()
			sshConn, chans, reqs, err := ssh.NewClientConn(rawConn, host, cfg)
			close(stopHandshakeWatch)
			if err != nil {
				_ = rawConn.Close()
				return nil, fmt.Errorf("ssh handshake %s: %w", host, err)
			}
			client := ssh.NewClient(sshConn, chans, reqs)

			stopSocketWatch := make(chan struct{})
			go func() {
				select {
				case <-ctx.Done():
					_ = client.Close()
				case <-stopSocketWatch:
				}
			}()
			conn, err := client.Dial("unix", remoteSock)
			close(stopSocketWatch)
			if err != nil {
				_ = client.Close()
				return nil, fmt.Errorf("ssh docker socket %s: %w", remoteSock, err)
			}
			return &sshTunnelConn{Conn: conn, client: client}, nil
		},
	}, nil
}

// sshTunnelConn closes both the forwarded socket channel and the owning SSH
// client. Without the second close, every streamed HTTP response would leave
// its SSH TCP connection and goroutines behind.
type sshTunnelConn struct {
	net.Conn
	client *ssh.Client
	once   sync.Once
	err    error
}

func (c *sshTunnelConn) Close() error {
	c.once.Do(func() {
		channelErr := c.Conn.Close()
		clientErr := c.client.Close()
		if channelErr != nil {
			c.err = channelErr
		} else {
			c.err = clientErr
		}
	})
	return c.err
}

var _ = filepath.Join // keep import stable across build tags
