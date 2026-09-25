# shellcheck shell=bash
# Disk usage inspection tools.

# Interactive disk usage explorer (ncdu).
scan() {
    ncdu "$@"
}

# Quick disk usage summary with depth 3 (dust). Defaults to $HOME.
qscan() {
    dust -d 3 "${@:-~}"
}
