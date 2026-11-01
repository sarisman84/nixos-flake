# shellcheck shell=bash
# Service restart helpers for the OpenChamber + opencode stack.
#
# OpenChamber is a user systemd service; the opencode server it talks to is a
# child of the openchamber process (not its own unit). Restarting openchamber
# therefore restarts both. Use `oc opencode` to bounce only the opencode server
# (e.g. to pick up newly installed agent skills) without touching the web UI.

# Restart OpenChamber and/or the opencode server it spawns.
# Usage: oc <openchamber|opencode|both>
oc() {
    local target="${1:-both}"
    case "$target" in
        openchamber|both)
            systemctl --user restart openchamber
            echo "openchamber restarted (the opencode server comes back with it)."
            ;;
        opencode)
            local pid
            pid=$(pgrep -f "opencode serve" | head -n1 || true)
            if [ -z "$pid" ]; then
                echo "no running 'opencode serve' found; restarting openchamber instead." >&2
                systemctl --user restart openchamber
                return
            fi
            echo "killing opencode server (pid $pid); waiting for openchamber to respawn it..."
            kill "$pid"
            local tries
            for tries in 1 2 3 4 5 6 7 8; do
                sleep 1
                if pgrep -f "opencode serve" >/dev/null 2>&1; then
                    echo "opencode server is back after ${tries}s (pid $(pgrep -f 'opencode serve' | head -n1))."
                    return
                fi
            done
            echo "opencode did not respawn on its own; restarting openchamber to bring it back." >&2
            systemctl --user restart openchamber
            ;;
        *)
            echo "usage: oc <openchamber|opencode|both>" >&2
            return 1
            ;;
    esac
}
