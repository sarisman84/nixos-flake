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
models_json="__models_json__"
jq_bin="__jq_bin__"
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

  --model <name>   use a local llama.cpp model; <name> is the key under
                   "llama.cpp" in models.json
  --cloud <name>   use a cloud model; <name> is the key under "opencode"
                   in models.json; skips the local llama-server
  (no model flag)  allowed for subcommands such as `models`, `run`, `mcp`;
                   a bare `opencode` is rejected

Examples:
  opencode --model qwen3.8-27b
  opencode --model bonsai-27b run "hello"
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

# Enforce: a bare `opencode` (no model flag and no subcommand) is rejected.
if [ $mode = "none" ] && [ ${#opencode_args[@]} -eq 0 ]; then
  echo "Error: select a model with --model (local) or --cloud (cloud)." >&2
  usage
  exit 2
fi

# Validate the chosen mode: the model must be registered in models.json.
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

# Map the requested llama.cpp model to the HF repo to launch, and alias it
# to the short opencode model name so the provider can route to it.
# Model registry: "$models_json" ({"<provider>": {"<name>": "<target>"}})
if [ $mode = "local" ]; then
  short_name="${model_name#llama.cpp/}"
  alias_name="$short_name"

  hf_model=""
  if [ -f "$models_json" ]; then
    hf_model=$("$jq_bin" -r --arg name "$short_name" \
      '.["llama.cpp"][$name] // empty' "$models_json" 2>/dev/null) || hf_model=""
  fi

  if [ -z "$hf_model" ]; then
    hf_model="$llama_default_model"
    echo "Unknown llama.cpp model '$model_name' (not in $models_json); falling back to default" >&2
  fi
fi

if [ $mode = "local" ] && ! "$curl_bin" --fail --silent --show-error "__llama_health_url__" >/dev/null 2>&1; then
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
