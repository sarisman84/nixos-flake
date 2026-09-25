# shellcheck shell=bash
# Entry point for all custom bash commands.
# When loaded via Nix (initExtra), the sub-files are inlined directly.
# When sourced manually (development), source the sub-files relative to this file.
if [ -n "${BASH_SOURCE[0]}" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/config.sh" ]; then
    source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
    source "$(dirname "${BASH_SOURCE[0]}")/git-commands.sh"
    source "$(dirname "${BASH_SOURCE[0]}")/system-tools.sh"
fi
