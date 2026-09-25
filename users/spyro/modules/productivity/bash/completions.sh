# shellcheck shell=bash
# Completions for custom bash commands defined in commands.sh
# Loaded via initExtra alongside commands.sh

# ── config {build|update|clear} ──────────────────────────────────────────

_config_hosts() {
    local flake_dir="${HOME}/config/nixos-flake"
    if [ -d "$flake_dir/hosts" ]; then
        local -a hosts=()
        local d
        for d in "$flake_dir"/hosts/*/; do
            hosts+=("$(basename "$d")")
        done
        COMPREPLY=( "${hosts[@]}" )
    fi
}

_config_subcommands() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    if [ "$COMP_CWORD" -eq 1 ]; then
        local subcommands="build update clear"
        read -r -a COMPREPLY < <(compgen -W "$subcommands" -- "$cur")
    elif [ "$COMP_CWORD" -eq 2 ]; then
        if [ "${COMP_WORDS[1]}" = "build" ] || [ "${COMP_WORDS[1]}" = "update" ]; then
            _config_hosts
        fi
    fi
    # No completions beyond position 2
}

complete -F _config_subcommands config

# ── branch {create|switch|list|merge} ────────────────────────────────────

_git_branches() {
    local -a branches=()
    local b
    # Local branches
    while IFS= read -r b; do
        branches+=("$b")
    done < <(git branch --format='%(refname:short)' 2>/dev/null)
    # Remote branches (query server directly — always up to date)
    while IFS= read -r b; do
        [ -n "$b" ] && branches+=("$b")
    done < <(git ls-remote --heads origin 2>/dev/null | awk '{print $2}' | sed 's|refs/heads/||')
    # Deduplicate (preserve order, case-insensitive)
    local -A seen=()
    local -a unique=()
    for b in "${branches[@]}"; do
        local key="${b,,}"
        if [ -z "${seen[$key]+x}" ]; then
            seen[$key]=1
            unique+=("$b")
        fi
    done
    COMPREPLY=( "${unique[@]}" )
}

_branch_subcommands() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    if [ "$COMP_CWORD" -eq 1 ]; then
        local subcommands="create switch list merge"
        read -r -a COMPREPLY < <(compgen -W "$subcommands" -- "$cur")
    elif [ "$COMP_CWORD" -eq 2 ]; then
        if [ "${COMP_WORDS[1]}" = "switch" ] || [ "${COMP_WORDS[1]}" = "merge" ]; then
            _git_branches
        fi
    fi
    # No completions beyond position 2
}

complete -F _branch_subcommands branch

# ── repo {link} ──────────────────────────────────────────────────────────

_repo_subcommands() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    if [ "$COMP_CWORD" -eq 1 ]; then
        read -r -a COMPREPLY < <(compgen -W "link" -- "$cur")
    fi
}

complete -F _repo_subcommands repo

# ── scan / qscan (directory completion) ──────────────────────────────────

_dir_completer() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    read -r -a COMPREPLY < <(compgen -d -- "$cur")
}

complete -F _dir_completer scan
complete -F _dir_completer qscan
