package main

import (
	"flag"
	"fmt"
	"os"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/colima-desktop/tui/internal/client"
	"github.com/colima-desktop/tui/internal/ui"
)

func main() {
	socket := flag.String("socket", "/tmp/colima-desktop.sock", "daemon unix socket")
	profile := flag.String("profile", "default", "colima profile")
	flag.Parse()

	cli, err := client.Dial(*socket)
	if err != nil {
		fmt.Fprintln(os.Stderr, "connect:", err)
		os.Exit(1)
	}
	defer cli.Close()

	if _, err := tea.NewProgram(ui.New(cli, *profile), tea.WithAltScreen()).Run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
