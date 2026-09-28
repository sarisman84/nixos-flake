# PROTOTYPE SKETCH — throwaway, not production. Slimmed wrapper: validation +
# exec only. Everything the old wrapper did around process lifetime is GONE:
# no llama-server spawn, no /health poll loop, no trap-kill, no -hf mapping.
# The systemd unit owns the proxy; the generated config owns the flags.
#
# Run with --dry-run to print the resolved state instead of execing opencode.
# (Pure bash, no jq: the sketch inlines a two-entry fixture registry with the
# same shape as models.json. The real thing reads the generated files.)
set -uo pipefail

PROXY_HEALTH_URL="http://127.0.0.1:8080/health"
# Fixture registry (sketch of generated models.json). Format per entry:
#   "<short-name> <provider> <hf-ref>"
FIXTURE_REGISTRY="qwen3.8-27b llama.cpp unsloth/Qwen3.8-27B-GGUF:UD-Q6_K_M
bonsai-27b llama.cpp prism-ml/Ternary-Bonsai-2-27B-gguf"
FIXTURE_DEFAULT_PROVIDER="llama.cpp"
FIXTURE_DEFAULT_NAME="qwen3.8-27b"
FIXTURE_CLOUD="muse-spark-1.3-contributor-free big-pickle"

DRY_RUN=0
SIMULATE_PROXY_DOWN=0
args=()
for a in "$@"; do
  case "$a" in
    --dry-run) DRY_RUN=1 ;;
    --simulate-proxy-down) SIMULATE_PROXY_DOWN=1 ;;
    *) args+=("$a") ;;
  esac
done
if [ ${#args[@]} -gt 0 ]; then set -- "${args[@]}"; else set --; fi

registry_has() { # $1=provider $2=name -> 0 if known
  local provider="$1" name="$2" line
  if [ "$provider" = "llama.cpp" ]; then
    while IFS= read -r line; do
      [ "${line%% *}" = "$name" ] && return 0
    done <<< "$FIXTURE_REGISTRY"
    return 1
  else
    for c in $FIXTURE_CLOUD; do [ "$c" = "$name" ] && return 0; done
    return 1
  fi
}

mode="none"; model_name=""
opencode_args=(); i=1; n=$#
while [ $i -le $n ]; do
  arg="${!i}"
  case "$arg" in
    --model) j=$((i+1)); model_name="${!j}"; mode="local"; i=$((i+2)) ;;
    --cloud) j=$((i+1)); model_name="${!j}"; mode="cloud"; i=$((i+2)) ;;
    *) opencode_args+=("$arg"); i=$((i+1)) ;;
  esac
done

if [ $mode = "none" ] && [ ${#opencode_args[@]} -eq 0 ]; then
  mode="local"; model_name="$FIXTURE_DEFAULT_NAME"
  [ "$FIXTURE_DEFAULT_PROVIDER" = "opencode" ] && mode="cloud"
fi

if [ $mode = "cloud" ]; then
  registry_has opencode "$model_name" || { echo "Error: unknown cloud model '$model_name'." >&2; exit 2; }
  model_name="opencode/$model_name"
elif [ $mode = "local" ]; then
  registry_has llama.cpp "$model_name" || { echo "Error: unknown local model '$model_name'." >&2; exit 2; }
  if [ $SIMULATE_PROXY_DOWN -eq 1 ]; then
    # PROPOSAL (react to this): fail fast, no silent cloud fallback.
    echo "Error: model proxy $PROXY_HEALTH_URL is not healthy." >&2
    echo "  check: systemctl --user status llama-swap" >&2
    echo "  logs:  journalctl --user -u llama-swap -e" >&2
    echo "  models available once it is back: qwen3.8-27b bonsai-27b" >&2
    exit 3
  fi
  model_name="llama.cpp/$model_name"
fi

if [ $mode != "none" ]; then
  opencode_args=(--model "$model_name" "${opencode_args[@]}")
fi

if [ $DRY_RUN -eq 1 ]; then
  echo "resolved opencode args: opencode ${opencode_args[*]:-<interactive>}"
  case "$mode" in
    local) echo "proxy action: none (persists); upstream '${model_name#llama.cpp/}' lazy-loads on first request, evicts predecessor immediately (swap-one), unloads after 120s idle" ;;
    cloud) echo "proxy action: bypassed entirely" ;;
    none)  echo "proxy action: passthrough (subcommand only, no model pinned)" ;;
  esac
  exit 0
fi

echo "(sketch would now exec: opencode ${opencode_args[*]})"
