#!/usr/bin/env bash
# Build the llm-agent single binary: bundle the React UI, then compile the bun
# server with the UI embedded. Produces ./llm-agent.
set -euo pipefail
cd "$(dirname "$0")"

echo "==> building the UI (vite)"
(cd ui && bun run build)

echo "==> compiling the binary (bun build --compile, UI embedded)"
bun build --compile \
  --asset 'ui/dist' \
  --outfile llm-agent \
  main.ts

echo "==> done: ./llm-agent"
echo "    run:  ./llm-agent serve"
