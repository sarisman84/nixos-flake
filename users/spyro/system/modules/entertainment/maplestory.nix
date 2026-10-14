{ pkgs, ... }:

let
  # Launch MapleStory (Steam app 216150, GE-Proton) inside gamescope so the
  # game renders at a lower internal resolution (small UI) and is upscaled to
  # the native 1440p panel. Magpie is Windows-only; gamescope is the Linux
  # equivalent (Valve's SteamOS microcompositor).
  #
  # Keep Steam running in the background so the game can authenticate; the
  # game (and its anti-cheat) is launched directly through the Proton prefix.
  #
  # NOTE: the ''${...} sequences below are escaped so Nix does not treat the
  # bash ${VAR:-default} expansions as Nix string interpolation.
  script = pkgs.writeText "maplestory-gamescope" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    STEAM_DIR="''${STEAM_HOME:-$HOME/.local/share/Steam}"
    APPID="216150"
    PROTON_NAME="''${MAPLE_PROTON:-GE-Proton11-3}"
    PROTON="$STEAM_DIR/compatibilitytools.d/$PROTON_NAME/proton"
    PREFIX="$STEAM_DIR/steamapps/compatdata/$APPID"
    GAME_EXE="$STEAM_DIR/steamapps/common/MapleStory/MapleStory.exe"

    # Internal game resolution (lower = smaller UI). 1080p is the sweet spot.
    GAME_W="''${MAPLE_GAME_W:-1920}"
    GAME_H="''${MAPLE_GAME_H:-1080}"

    # Output/display resolution (native panel).
    OUT_W="''${MAPLE_OUT_W:-2560}"
    OUT_H="''${MAPLE_OUT_H:-1440}"

    # Upscaler filter: fsr | nis | linear | nearest | pixel
    FILTER="''${MAPLE_FILTER:-fsr}"

    for f in "$PROTON" "$GAME_EXE"; do
      if [ ! -e "$f" ]; then
        echo "maplestory-gamescope: missing $f" >&2
        exit 1
      fi
    done

    export STEAM_COMPAT_CLIENT_INSTALL_PATH="$STEAM_DIR"
    export STEAM_COMPAT_DATA_PATH="$PREFIX"

    # Make the Vulkan loader findable: Proton's launcher does
    # CDLL('libvulkan.so.1'), which fails unless the loader is on the path.
    export LD_LIBRARY_PATH="${pkgs.vulkan-loader}/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

    exec ${pkgs.gamescope}/bin/gamescope \
      --backend wayland \
      -w "$GAME_W" -h "$GAME_H" \
      -W "$OUT_W" -H "$OUT_H" \
      -S fit \
      -F "$FILTER" \
      -- \
      "$PROTON" run "$GAME_EXE"
  '';

  # freedesktop entry so KDE Plasma (KRunner + start menu) can find it.
  # Installed into share/applications/, which lands in
  # /run/current-system/sw/share/applications (on XDG_DATA_DIRS).
  desktop = pkgs.writeText "maplestory-gamescope.desktop" ''
    [Desktop Entry]
    Type=Application
    Version=1.0
    Name=MapleStory
    GenericName=MMORPG
    Comment=Launch MapleStory via gamescope (1080p render, upscaled to 1440p)
    Exec=maplestory-gamescope
    Icon=applications-games
    Categories=Game;
    Terminal=false
  '';

  # buildEnv (used by environment.systemPackages) can only merge directory
  # packages, so wrap the script file into a proper $out/bin/ package.
  maplestory-gamescope = pkgs.runCommand "maplestory-gamescope" { } ''
    mkdir -p $out/bin $out/share/applications
    install -m 0755 ${script} $out/bin/maplestory-gamescope
    install -m 0644 ${desktop} $out/share/applications/maplestory-gamescope.desktop
  '';
in

{
  environment.systemPackages = [
    pkgs.gamescope
    maplestory-gamescope
  ];
}
