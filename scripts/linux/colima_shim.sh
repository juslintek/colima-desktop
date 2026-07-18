#!/usr/bin/env bash
# scripts/linux/colima_shim.sh
#
# CI-only stub for the `colima` binary.
#
# Purpose:
#   DependencyManager::is_colima_installed() uses which::which("colima") — if
#   `colima` is not on PATH the app shows the onboarding window instead of the
#   main UI, making all AT-SPI captures identical onboarding snapshots.
#
#   This shim is placed on PATH before the explorer is launched so the app
#   sees colima as "installed" and shows the real main window with the sidebar.
#   The shim never actually manages VMs; it just satisfies the presence check.
#
# Usage (called implicitly via PATH manipulation, not directly):
#   colima --version          → prints version string, exit 0
#   colima version            → same
#   colima status [--json]    → prints a JSON status stub, exit 0
#   colima list   [--json]    → prints a JSON list stub (one running instance), exit 0
#   colima start  [args...]   → prints "started", exit 0
#   colima stop   [args...]   → prints "stopped", exit 0
#   colima delete [args...]   → prints "deleted", exit 0
#   colima ssh-config [args]  → prints an empty SSH config, exit 0
#   <anything else>           → prints error to stderr, exit 1
#
# Do NOT put this file on a production PATH.  It is intentionally incomplete.

COLIMA_SHIM_VERSION="0.6.99-ci-shim"

cmd="${1:-}"

case "$cmd" in
    --version|version)
        echo "colima version ${COLIMA_SHIM_VERSION}"
        echo "git commit: ci-shim"
        echo ""
        echo "runtime: docker"
        echo "arch: x86_64"
        echo "client: v24.0.0"
        echo "server: v24.0.0"
        exit 0
        ;;

    status)
        # Support --json flag
        if [[ "${2:-}" == "--json" || "${3:-}" == "--json" ]]; then
            cat <<'JSON'
{"display_name":"colima","driver":"ci-shim","arch":"x86_64","runtime":"docker","mount_type":"virtiofs","docker_socket":"unix:///tmp/colima-ci-shim.sock","containerd_socket":"unix:///tmp/colima-ci-shim-containerd.sock","kubernetes":false,"cpu":2,"memory":2147483648,"disk":107374182400}
JSON
        else
            echo "colima is running (ci-shim)"
        fi
        exit 0
        ;;

    list)
        if [[ "${2:-}" == "--json" || "${3:-}" == "--json" ]]; then
            cat <<'JSON'
{"name":"default","status":"Running","arch":"x86_64","cpus":2,"memory":2147483648,"disk":107374182400,"runtime":"docker","ipAddress":""}
JSON
        else
            printf "%-20s %-10s %-10s\n" "PROFILE" "STATUS" "ARCH"
            printf "%-20s %-10s %-10s\n" "default" "Running" "x86_64"
        fi
        exit 0
        ;;

    start)
        echo "info  using colima executable found in context: ci-shim"
        echo "info  starting colima"
        echo "info  colima is already running, ignoring"
        exit 0
        ;;

    stop)
        echo "info  stopping colima"
        echo "info  done"
        exit 0
        ;;

    restart)
        echo "info  restarting colima"
        echo "info  done"
        exit 0
        ;;

    delete)
        echo "info  deleting colima"
        echo "info  done"
        exit 0
        ;;

    ssh-config)
        # Print a minimal, syntactically valid SSH config block so callers
        # that parse the output don't crash.
        cat <<'SSHCONF'
Host colima
  HostName 127.0.0.1
  User colima
  Port 22222
  IdentityFile /tmp/colima-ci-shim-id
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
SSHCONF
        exit 0
        ;;

    template)
        # colima template --print just prints a path; avoid opening an editor
        echo "/tmp/colima-ci-shim-template.yaml"
        exit 0
        ;;

    kubernetes|k8s|kube|k3s|k)
        echo "info  kubernetes (ci-shim): no-op"
        exit 0
        ;;

    update|up|u)
        echo "info  update (ci-shim): no-op"
        exit 0
        ;;

    prune)
        echo "info  prune (ci-shim): no-op"
        exit 0
        ;;

    model)
        echo "info  model (ci-shim): no-op"
        exit 0
        ;;

    clone)
        echo "info  clone (ci-shim): no-op"
        exit 0
        ;;

    "")
        # bare `colima` with no args — print usage hint and exit 1 (same as real colima)
        echo "Colima CLI (ci-shim ${COLIMA_SHIM_VERSION})" >&2
        echo "Use: colima [start|stop|status|list|delete|version|ssh-config]" >&2
        exit 1
        ;;

    *)
        echo "colima: unknown command \"${cmd}\" (ci-shim — unrecognized subcommand)" >&2
        exit 1
        ;;
esac
