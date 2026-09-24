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
    NIXOS_LOG="${NIXOS_LOG:-1}" sudo nixos-rebuild switch --flake ~/config/nixos-flake/#"$*" --show-trace
}

config_update() {
    nix flake update --flake ~/config/nixos-flake/
    sudo nixos-rebuild switch --flake ~/config/nixos-flake/#"$*" --show-trace --upgrade
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