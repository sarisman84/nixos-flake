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
llama_default_model="__llama_model__"
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

usage() {
  cat >&2 <<'EOF'
Usage:
  opencode --model llama.cpp/<name> [opencode args...]
  opencode --cloud opencode/<name> [opencode args...]
  opencode [opencode args...]

  --model <name>   use a local llama.cpp model (name may be any llama.cpp/<model>)
  --cloud <name>   use an OpenCode Zen cloud model (name must be opencode/<model>);
                   skips the local llama-server
  (no model flag)  allowed for subcommands such as `models`, `run`, `mcp`;
                   a bare `opencode` is rejected

Examples:
  opencode --model llama.cpp/qwen3.8-27b
  opencode --model llama.cpp/bonsai-27b run "hello"
  opencode --cloud opencode/muse-spark-1.3-contributor-free
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
        echo "Error: --model requires a value (e.g. llama.cpp/qwen3.8-27b)." >&2
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
        echo "Error: --cloud requires a value (e.g. opencode/big-pickle)." >&2
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

# Enforce: a bare `opencode` (no model flag and no subcommand) is rejected.
if [ $mode = "none" ] && [ ${#opencode_args[@]} -eq 0 ]; then
  echo "Error: select a model with --model (local) or --cloud (cloud)." >&2
  usage
  exit 2
fi

# Validate the chosen mode.
if [ $mode = "cloud" ]; then
  if [[ "$model_name" != opencode/* ]]; then
    echo "Error: --cloud requires a cloud model (opencode/<name>), got '$model_name'." >&2
    usage
    exit 2
  fi
elif [ $mode = "local" ]; then
  if [[ "$model_name" != llama.cpp/* ]]; then
    echo "Error: --model requires a local model (llama.cpp/<name>), got '$model_name'." >&2
    usage
    exit 2
  fi
fi

# Build the final opencode invocation: --model <name> followed by the rest.
if [ $mode != "none" ]; then
  opencode_args=(--model "$model_name" "${opencode_args[@]}")
fi

# Map the requested llama.cpp model to the HF repo to launch, and alias it
# to the short opencode model name so the provider can route to it.
if [ $mode = "local" ]; then
  case "${model_name#llama.cpp/}" in
    qwen3.8-27b)
      hf_model="unsloth/Qwen3.8-27B-GGUF:UD-Q6_K_M"
      alias_name="qwen3.8-27b"
      ;;
    bonsai-27b)
      hf_model="prism-ml/Ternary-Bonsai-2-27B-gguf"
      alias_name="bonsai-27b"
      ;;
    *)
      hf_model="unsloth/Qwen3.8-27B-GGUF:UD-Q6_K_M"
      alias_name="${model_name#llama.cpp/}"
      echo "Unknown llama.cpp model '$model_name'; falling back to default" >&2
      ;;
  esac
else
  hf_model="$llama_default_model"
  alias_name="qwen3.8-27b"
fi

if [ $mode = "cloud" ]; then
  echo "Cloud mode: skipping llama-server"
elif ! "$curl_bin" --fail --silent --show-error "__llama_health_url__" >/dev/null 2>&1; then
  echo "Starting llama-server for $hf_model"
  "$llama_bin" -hf "$hf_model" -a "$alias_name" --host "__llama_host__" --port "__llama_port__" \
    --jinja \
    --reasoning off \
    >"$log_file" 2>&1 &
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
