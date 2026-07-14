//go:build !windows

package docker

import (
	"fmt"
	"net/http"
)

// wsl2Transport is Windows-only; on other platforms it is unavailable.
func wsl2Transport(_ Target) (http.RoundTripper, string, error) {
	return nil, "", fmt.Errorf("wsl2 backend is only available on Windows")
}
