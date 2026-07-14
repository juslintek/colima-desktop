//go:build windows

package docker

import (
	"context"
	"net"
	"net/http"
	"time"

	winio "github.com/Microsoft/go-winio"
)

// wsl2Transport dials the local Windows/WSL2 Docker engine npipe.
func wsl2Transport(_ Target) (http.RoundTripper, string, error) {
	pipe := `\\.\pipe\docker_engine`
	return &http.Transport{
		DialContext: func(ctx context.Context, _, _ string) (net.Conn, error) {
			d := 10 * time.Second
			return winio.DialPipe(pipe, &d)
		},
	}, "http://docker", nil
}
