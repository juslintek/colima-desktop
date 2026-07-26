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
	endpoint := client.DefaultEndpoint()
	flag.StringVar(&endpoint, "endpoint", endpoint, "daemon endpoint (unix:/path or tcp:127.0.0.1:port)")
	flag.StringVar(&endpoint, "socket", endpoint, "legacy alias for -endpoint")
	profile := flag.String("profile", "default", "colima profile")
	onboarding := flag.Bool("onboarding", false, "show dependency onboarding screen on startup")
	flag.Parse()

	cli, err := client.Dial(endpoint)
	if err != nil {
		fmt.Fprintln(os.Stderr, "connect:", err)
		os.Exit(1)
	}
	defer cli.Close()

	var m tea.Model
	if *onboarding {
		ob := ui.NewOnboardingModel()
		m = ui.NewWithOnboarding(cli, *profile, ob)
	} else {
		m = ui.New(cli, *profile)
	}

	if _, err := tea.NewProgram(m, tea.WithAltScreen()).Run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
