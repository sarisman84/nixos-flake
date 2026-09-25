# shellcheck shell=bash
# NixOS flake deployment commands.

# Dispatches to the appropriate config subcommand.
config() {
    local cmd="$1"
    shift

    case "$cmd" in
        build)
            _config_build "$@"
            ;;
        update)
            _config_update "$@"
            ;;
        clear)
            _config_clear "$@"
            ;;
        -h | --help)
            echo "Usage: config {build|update|clear} [args...]"
            return 1
            ;;
        *)
            _config_edit "$@"
            ;;
    esac
}

# Evaluate the flake and switch the system to the given host config.
_config_build() {
    local host="$*"
    local start

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  ⚙  Deploying ${host}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  Evaluating flake & building system..."
    start=$SECONDS

    sudo nixos-rebuild switch --flake ~/config/nixos-flake/#"$*" --show-trace
    local status=$?

    local elapsed=$((SECONDS - start))
    echo ""

    if [ $status -eq 0 ]; then
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "  ✔  ${host} deployed in ${elapsed}s"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        _config_prune_generations
    else
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "  ✘  Deploy failed (exit ${status})"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    fi

    return $status
}

# Delete all but the newest N NixOS system generations.
# N is read from $NIXOS_KEEP_GENERATIONS (default 3). No-op when there are
# fewer than N+1 generations to prune.
_config_prune_generations() {
    local keep="${NIXOS_KEEP_GENERATIONS:-3}"
    local profile="/nix/var/nix/profiles/system"
    local gens total
    local -a toDelete=()

    gens=$(sudo nix-env -p "$profile" --list-generations 2>/dev/null | awk '{print $1}')
    total=$(echo "$gens" | grep -c .)

    # Nothing to prune unless we have more than 'keep' generations.
    [ "$total" -le "$keep" ] && return 0

    # Oldest (total - keep) generation numbers, newest 'keep' preserved.
    while IFS= read -r gen; do
        toDelete+=("$gen")
    done < <(echo "$gens" | sort -n | head -n -"$keep")

    if [ "${#toDelete[@]}" -gt 0 ]; then
        echo ""
        echo "  🧹 Pruning system generations (keeping newest ${keep}): ${toDelete[*]}"
        # --delete-generations removes the listed generations and automatically
        # reclaims their store paths. Do NOT also run a full `nix-collect-garbage
        # -d` here — that sweeps *every* unreferenced path (including the
        # generations we want to keep), collapsing the profile to one build.
        sudo nix-env -p "$profile" --delete-generations "${toDelete[@]}"
    fi
}

# Update flake inputs, then build and switch to the given host config.
_config_update() {
    local host="$*"

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  ↻  Updating & deploying ${host}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  Updating flake inputs..."

    nix flake update --flake ~/config/nixos-flake/
    if [ $? -ne 0 ]; then
        echo ""
        echo "  ✘  Flake update failed"
        return 1
    fi

    echo ""
    echo "  Building & switching..."

    sudo nixos-rebuild switch --flake ~/config/nixos-flake/#"$*" --show-trace --upgrade
    local status=$?

    echo ""
    if [ $status -eq 0 ]; then
        echo "  ✔  ${host} updated & deployed"
    else
        echo "  ✘  Deploy failed (exit ${status})"
    fi

    return $status
}

# Open the nixos-flake repo in VSCode.
_config_edit() {
    code ~/config/nixos-flake
}

# Collect Nix garbage and reboot into the last known good config.
_config_clear() {
    sudo nix-collect-garbage -d
    sudo /run/current-system/bin/switch-to-configuration boot
}
