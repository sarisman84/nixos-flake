config(){
    local cmd="$1"
    shift

    case "$cmd" in
        build)
            config_build "$@"
            ;;
        update)
            config_update "$@"
            ;;
        clear)
            config_clear "$@"
            ;;
        -h | --help)
            echo "Usage: config {build|update|*} [args...]"
            return 1 
            ;;

        *)
            config_edit "$@"
            ;;
    esac
}

branch() {
    local cmd="$1"
    shift

    case "$cmd" in
       create)
            vc_create "$@"
            ;;
        switch)
            vc_switch "$@"
            ;;
        list)
            vc_list "$@"
            ;;
        merge)
            vc_merge "$@"
            ;;
        * | -h | --help)
            echo "Shortcuts for Git CLI branch commands."
            echo "Usage: branch {create|switch|list} [args..]"
            return 1
        ;;
    esac

}

repo() {
    local cmd="$1"
    shift

    case "$cmd" in
        link)
            vc_repoLink "$@"
            ;;
    * | -h | --help)
        echo "Shortcuts for Git CLI repository commands."
        echo "Usage: repo {link} [args..]"
        return 1
        ;;

    esac
}




commit() {
    local cmd="$1"

    case "$cmd" in
    -h | --help)
        echo "Command: commit - [message body]"
        echo "Adds all changed and new files and commits a short message."
        echo "Uses: 'git add .' and 'git commit -m' under the hood."
        return 1
    ;;
    *)
        git add .
        git commit -m "$*"
    ;;
    esac

}

push() {
    local cmd="$1"
    shift

    case "$cmd" in
    -h | --help)
        echo "Command: push"
        echo "Shorthand for 'git push'"
        return 1
    ;;
    *)
        git push
    ;;
    esac
   
}

pull() {
    local cmd="$1"
    shift

    case "$cmd" in
    -h | --help)
        echo "Command: pull"
        echo "Shorthand for 'git pull' with the --rebase argument to automatically rebase."
        return 1
    ;;
    *)
    git pull --rebase
    ;;
    esac
    
}

check() {
    local cmd="$1"
    shift

    case "$cmd" in
    -h | --help)
        echo "Command: check"
        echo "Shorthand for 'git status'."
        return 1
    ;;
    *)
    git status
    ;;
    esac
}





config_build() {
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
        # Prune old system generations so repeated builds don't pile up.
        # Only runs on success so a failed build never drops a good generation.
        config_prune_generations
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
config_prune_generations() {
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

config_update() {
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

config_edit() {
    code ~/config/nixos-flake
}

config_clear() {
    sudo nix-collect-garbage -d
    sudo /run/current-system/bin/switch-to-configuration boot
}


vc_create() {
    git switch -c "$*"
    git push --set-upstream origin "$*"
}

vc_list() {
    git branch;
}

vc_switch() {
    git switch "$*"
}

vc_repoLink() {
    git remote add origin "$*"
}

vc_merge() {
    git merge "$1"
}

scan() {
    ncdu "$@"
}

qscan() {
    dust -d 3 "${@:-~}"
}