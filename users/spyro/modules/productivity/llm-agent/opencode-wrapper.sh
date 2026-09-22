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
llama_bin="__llama_bin__"
opencode_bin="__opencode_bin__"
log_file="/tmp/opencode-llama-server.log"
server_pid=""

cleanup() {
  if [ -n "$server_pid" ]; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

opencode_args=("$@")
cloud=false
args=()

for arg in "${opencode_args[@]}"; do
  if [ "$arg" = "--cloud" ]; then
    cloud=true
  else
    args+=("$arg")
  fi
done

if [ ${#args[@]} -gt 0 ] && [[ "${args[0]}" == */* ]]; then
  opencode_args=(--model "${args[0]}" "${args[@]:1}")
else
  opencode_args=("${args[@]}")
fi

if [ "$cloud" = true ]; then
  echo "Cloud mode: skipping llama-server"
elif ! "$curl_bin" --fail --silent --show-error "__llama_health_url__" >/dev/null 2>&1; then
  echo "Starting llama-server for __llama_model__"
  "$llama_bin" -hf "__llama_model__" --host "__llama_host__" --port "__llama_port__" >"$log_file" 2>&1 &
  server_pid=$!

  for _ in $(seq 1 180); do
    if "$curl_bin" --fail --silent "__llama_health_url__" >/dev/null 2>&1; then
      break
    fi

    if ! kill -0 "$server_pid" 2>/dev/null; then
      echo "llama-server exited during startup" >&2
      tail -n 50 "$log_file" >&2 || true
      break
    fi

    sleep 1
  done

  if ! "$curl_bin" --fail --silent "__llama_health_url__" >/dev/null 2>&1; then
    echo "llama-server is not healthy; falling back to plain opencode" >&2
    tail -n 50 "$log_file" >&2 || true
  fi
fi

"$opencode_bin" "${opencode_args[@]}"
