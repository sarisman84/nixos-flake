set -euo pipefail

env_dir="__env_dir__"
if [ -d "$env_dir" ]; then
  for env_file in "$env_dir"/*.env; do
    [ -e "$env_file" ] || continue
    set -a
    . "$env_file"
    set +a
  done
fi

curl_bin="__curl_bin__"
swap_bin="__llama_swap_bin__"
swap_config="__swap_config__"
opencode_bin="__opencode_bin__"
models_json="__models_json__"
jq_bin="__jq_bin__"
pgrep_bin="__pgrep_bin__"
oc_name="__oc_name__"
oc_desktop_name="__oc_desktop_name__"
swap_name="__swap_name__"
log_file="__log_file__"

# The swap backend is shared across opencode instances. Instances are tracked
# by process name: when the last one exits, the backend (llama-swap and its
# llama-server children) is stopped gracefully, so no manual cleanup is
# needed. opencode-desktop is counted as an instance too — it talks to the
# same backend.

ran_opencode=0

# True if $1 is a live $2 instance. Neither /proc comm nor the /proc exe
# basename can be trusted on its own: the kernel truncates comm to 15
# characters ("opencode-desktop" is 16), and Nix wrapping means the exe is
# never literally "opencode" — the wrapper script runs as bash, and the real
# binary is .opencode-wrapped. So accept a process whose exe basename OR any
# argv basename equals $2. Our own PID is never a match (the wrapper's EXIT
# trap would otherwise count itself and never stop the backend).
matches_instance() {
  local pid="$1" want="$2" exe arg
  [ "$pid" != "$$" ] || return 1
  exe=$(readlink "/proc/$pid/exe" 2>/dev/null) || return 1
  [ "${exe##*/}" = "$want" ] && return 0
  while IFS= read -r -d '' arg; do
    [ "${arg##*/}" = "$want" ] && return 0
  done <"/proc/$pid/cmdline" 2>/dev/null
  return 1
}

# True if any opencode CLI or opencode-desktop instance is still running.
# Our own opencode child has already exited (and been reaped) by the time
# this is called from the EXIT trap, so it is not counted. Candidates come
# from a loose command-line pgrep; the check above filters the rest.
other_opencode_running() {
  local pid
  for pid in $("$pgrep_bin" -f "(^|/)($oc_name|$oc_desktop_name)( |$)" 2>/dev/null || true); do
    if matches_instance "$pid" "$oc_name" || matches_instance "$pid" "$oc_desktop_name"; then
      return 0
    fi
  done
  return 1
}

# Stop the shared backend: SIGTERM llama-swap (its handler drains requests
# and stops the upstream llama-server processes), then SIGKILL as a
# backstop. No-op when nothing is running.
stop_swap_backend() {
  local pid
  for pid in $("$pgrep_bin" -f "(^|/)$swap_name( |$)" 2>/dev/null || true); do
    matches_instance "$pid" "$swap_name" || continue
    echo "All opencode instances closed; stopping $swap_name (pid $pid)"
    kill -TERM "$pid" 2>/dev/null || true
    local waited=0
    while [ $waited -lt 20 ] && kill -0 "$pid" 2>/dev/null; do
      sleep 1
      waited=$((waited + 1))
    done
    if kill -0 "$pid" 2>/dev/null; then
      echo "$swap_name (pid $pid) did not exit; sending SIGKILL" >>"$log_file"
      kill -KILL "$pid" 2>/dev/null || true
    fi
  done
}

trap '
  if [ "$ran_opencode" = "1" ] && ! other_opencode_running; then
    stop_swap_backend
  fi
' EXIT

list_models() {
  local section="$1"
  echo "Available $section models (from $models_json):"
  if [ -f "$models_json" ]; then
    "$jq_bin" -r --arg section "$section" \
      '.[$section] // {} | keys[]' "$models_json" 2>/dev/null | while IFS= read -r name; do
        echo "  $name"
      done
  else
    echo "  (registry not found)"
  fi
}

usage() {
  cat >&2 <<'EOF'
Usage:
  opencode --model <name> [opencode args...]
  opencode --cloud <name> [opencode args...]
  opencode [opencode args...]

  --model <name>   use a local model; <name> is the key under "llama.cpp"
                   in models.json. The swap backend is ensured (started if
                   missing); the picked model loads on demand.
  --cloud <name>   use a cloud model; <name> is the key under "opencode"
                   in models.json; no local backend is touched.
  (no model flag)  use the default model set in models.json ("default" key:
                   {"provider", "name"}); a bare `opencode` launches an
                   interactive session with that default

Examples:
  opencode                        # default model from models.json
  opencode --model qwen3-8b
  opencode --model qwen3.8-27b run "hello"
  opencode --cloud big-pickle
  opencode models
  opencode run "hello"
EOF
}

mode="none"        # none | local | cloud
model_name=""
opencode_args=()
i=1
n=$#
while [ $i -le $n ]; do
  arg="${!i}"
  case "$arg" in
    --model)
      if [ $mode != "none" ]; then
        echo "Error: --model and --cloud are mutually exclusive." >&2
        usage
        exit 2
      fi
      if [ $((i + 1)) -gt $n ]; then
        echo "Error: --model requires a value (a model name from models.json)." >&2
        usage
        exit 2
      fi
      j=$((i + 1))
      model_name="${!j}"
      mode="local"
      i=$((i + 2))
      ;;
    --cloud)
      if [ $mode != "none" ]; then
        echo "Error: --model and --cloud are mutually exclusive." >&2
        usage
        exit 2
      fi
      if [ $((i + 1)) -gt $n ]; then
        echo "Error: --cloud requires a value (a model name from models.json)." >&2
        usage
        exit 2
      fi
      j=$((i + 1))
      model_name="${!j}"
      mode="cloud"
      i=$((i + 2))
      ;;
    *)
      opencode_args+=("$arg")
      i=$((i + 1))
      ;;
  esac
done

# A bare `opencode` (no model flag, no subcommand) uses the default model
# from models.json. Subcommands (models, run, mcp, ...) pass through as-is.
if [ $mode = "none" ] && [ ${#opencode_args[@]} -eq 0 ]; then
  if [ ! -f "$models_json" ]; then
    echo "Error: cannot resolve default model ($models_json not found)." >&2
    exit 2
  fi

  def_provider=$("$jq_bin" -r '.default.provider // empty' "$models_json" 2>/dev/null)
  def_name=$("$jq_bin" -r '.default.name // empty' "$models_json" 2>/dev/null)

  if [ -z "$def_provider" ] || [ -z "$def_name" ]; then
    echo "Error: default model not set in $models_json (need \"default\": {\"provider\", \"name\"})." >&2
    exit 2
  fi

  case "$def_provider" in
    llama.cpp)
      mode="local"
      model_name="$def_name"
      ;;
    opencode)
      mode="cloud"
      model_name="$def_name"
      ;;
    *)
      echo "Error: unknown default provider '$def_provider' in $models_json (expected llama.cpp or opencode)." >&2
      exit 2
      ;;
  esac
fi

# Validate the chosen mode: the model must be registered in models.json.
# Registry entries are objects ({displayName, hfRef, options}); only the
# keys matter here — the swap backend owns the model-to-command mapping.
if [ $mode = "cloud" ]; then
  if [ ! -f "$models_json" ] || ! "$jq_bin" -e --arg name "$model_name" \
      '.opencode | has($name)' "$models_json" >/dev/null 2>&1; then
    echo "Error: unknown cloud model '$model_name' (not in $models_json)." >&2
    list_models opencode >&2
    exit 2
  fi
  model_name="opencode/$model_name"
elif [ $mode = "local" ]; then
  if [ ! -f "$models_json" ] || ! "$jq_bin" -e --arg name "$model_name" \
      '.["llama.cpp"] | has($name)' "$models_json" >/dev/null 2>&1; then
    echo "Error: unknown local model '$model_name' (not in $models_json)." >&2
    list_models llama.cpp >&2
    exit 2
  fi
  model_name="llama.cpp/$model_name"
fi

# Build the final opencode invocation: --model <name> followed by the rest.
if [ $mode != "none" ]; then
  opencode_args=(--model "$model_name" "${opencode_args[@]}")
fi

# Local mode needs the shared swap backend. If it is already healthy,
# nothing happens; otherwise it is started. The EXIT trap (above) stops it
# when this turns out to be the last opencode instance.
if [ $mode = "local" ] && ! "$curl_bin" --fail --silent --show-error "__llama_health_url__" >/dev/null 2>&1; then
  echo "Starting llama-swap (models load on demand)"
  "$swap_bin" -config "$swap_config" -listen "__llama_host__:__llama_port__" \
    >"$log_file" 2>&1 &
  swap_pid=$!

  for _ in $(seq 1 180); do
    if "$curl_bin" --fail --silent "__llama_health_url__" >/dev/null 2>&1; then
      break
    fi

    if ! kill -0 "$swap_pid" 2>/dev/null; then
      echo "llama-swap exited during startup" >&2
      tail -n 50 "$log_file" >&2 || true
      break
    fi

    sleep 1
  done

  if ! "$curl_bin" --fail --silent "__llama_health_url__" >/dev/null 2>&1; then
    echo "llama-swap is not healthy; falling back to plain opencode" >&2
    tail -n 50 "$log_file" >&2 || true
  fi
fi

# From here on a session is actually running; on exit the trap shuts the
# backend down if this was the last opencode instance.
ran_opencode=1
"$opencode_bin" "${opencode_args[@]}"
