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
    esac

}

repo() {
    local cmd="$1"
    shift

    case "$cmd" in
        link)
            vc_repoLink "$@"
    esac
}




commit(){
    git add .
    git commit -m "$1"
}

push(){
    git push
}

pull(){
    git pull --rebase
}

check(){
    git status;
}





config_build(){
    sudo nixos-rebuild switch --flake ~/config/nixos-config/#"$1" --show-trace
}

config_update(){
    nix flake update --flake ~/config/nixos-flake/
    sudo nixos-rebuild switch --flake ~/config/nixos-flake/#"$1" --show-trace --upgrade
}

config_edit(){
    code ~/config/nixos-flake
}


vc_create() {
    git switch -c "$1"
    git push --set-upstream origin "$1"
}

vc_list() {
    git branch;
}

vc_switch() {
    git switch "$1"
}

vc_repoLink(){
    git remote add origin "$1"
}