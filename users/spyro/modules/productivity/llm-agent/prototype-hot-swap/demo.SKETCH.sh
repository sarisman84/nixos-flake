# PROTOTYPE SKETCH — throwaway demo harness. Trivial to run, bash only:
#   bash users/spyro/modules/productivity/llm-agent/prototype-hot-swap/demo.SKETCH.sh
# Each case prints the FULL resolved state so you can see what changed.
W="$(dirname "$0")/opencode-wrapper.SKETCH.sh"

run() { echo "### $ $*"; bash "$W" --dry-run "$@"; echo; }

run
run --model bonsai-27b run '"hello"'
run --cloud big-pickle
run --model nope || true
run --model qwen3.8-27b --simulate-proxy-down || true
run models
