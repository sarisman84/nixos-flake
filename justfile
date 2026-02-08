set working-directory := '.'
set positional-arguments

build:
    echo '[LOG][Justfile]: Creating new build to switch to.'
    sudo nixos-rebuild switch --flake .#$1
    echo '[OK][Justfile]: Build created!'
clear:
    echo '[LOG][Justfile]: Clearing existing builds.'
    sudo nix-collect-garbage -d
    sudo /run/current-system/bin/switch-to-configuration boot
    echo '[OK][Justfile]: Old builds deleted!'

update:
    echo '[LOG][Justfile]: Creating new build with updated packages to switch to.'
    sudo nixos-rebuild switch --flake .#$1 --upgrade
    echo '[OK][Justfile]: Packages updated | Build created!'