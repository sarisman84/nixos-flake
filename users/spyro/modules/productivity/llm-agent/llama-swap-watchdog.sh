set -euo pipefail

# Periodic watchdog (systemd user timer, ~30s): stops the shared llama-swap
# backend when no opencode instance (CLI or desktop) is running and the
# backend has been up long enough to not be a startup in progress. Catches
# what the wrapper's on-exit hook cannot: the desktop app closing last, and
# wrappers that die without running their EXIT trap.

pgrep_bin="__pgrep_bin__"
oc_name="__oc_name__"
oc_desktop_name="__oc_desktop_name__"
swap_name="__swap_name__"
log_file="__log_file__"

# Never touch a backend younger than this many seconds: a wrapper starts
# llama-swap and only milliseconds later spawns opencode.
min_uptime=90

# True if $1 is a live process whose executable basename is exactly $2.
# /proc comm is NOT used: the kernel truncates it to 15 characters and
# "opencode-desktop" is 16.
is_live_pid() {
  local pid="$1" want="$2" exe
  exe=$(readlink "/proc/$pid/exe" 2>/dev/null) || return 1
  [ "${exe##*/}" = "$want" ]
}

# True if any opencode CLI or opencode-desktop instance is running.
# Candidates come from a loose command-line pgrep; the exe check above
# filters the rest.
oc_running() {
  local pid
  for pid in $("$pgrep_bin" -f "(^|/)($oc_name|$oc_desktop_name)( |$)" 2>/dev/null || true); do
    if is_live_pid "$pid" "$oc_name" || is_live_pid "$pid" "$oc_desktop_name"; then
      return 0
    fi
  done
  return 1
}

swap_pid=""
for pid in $("$pgrep_bin" -f "(^|/)$swap_name( |$)" 2>/dev/null || true); do
  if is_live_pid "$pid" "$swap_name"; then
    swap_pid="$pid"
    break
  fi
done
[ -n "$swap_pid" ] || exit 0

oc_running && exit 0

age=$(( $(date +%s) - $(stat -c %Y "/proc/$swap_pid" 2>/dev/null || echo 0) ))
[ "$age" -ge "$min_uptime" ] || exit 0

echo "$(date -Is) watchdog: no opencode instances; stopping $swap_name (pid $swap_pid)" >>"$log_file"
kill -TERM "$swap_pid" 2>/dev/null || true
waited=0
while [ $waited -lt 20 ] && kill -0 "$swap_pid" 2>/dev/null; do
  sleep 1
  waited=$((waited + 1))
done
if kill -0 "$swap_pid" 2>/dev/null; then
  echo "$(date -Is) watchdog: $swap_name (pid $swap_pid) did not exit; sending SIGKILL" >>"$log_file"
  kill -KILL "$swap_pid" 2>/dev/null || true
fi
