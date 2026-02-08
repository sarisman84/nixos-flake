set working-directory := '.'
set positional-arguments

build host:
    echo '[LOG][Justfile]: Creating new build to switch to.'
    sudo nixos-rebuild switch --flake .#{{host}} --show-trace
    echo '[OK][Justfile]: Build created!'
clear:
    echo '[LOG][Justfile]: Clearing existing builds.'
    sudo nix-collect-garbage -d
    sudo /run/current-system/bin/switch-to-configuration boot
    echo '[OK][Justfile]: Old builds deleted!'

update host:
    echo '[LOG][Justfile]: Creating new build with updated packages to switch to.'
    sudo nixos-rebuild switch --flake .#{{host}} --show-trace --upgrade
    echo '[OK][Justfile]: Packages updated | Build created!'