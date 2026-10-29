{
  pkgs,
  lib,
  ...
}: let
  # The Unity CLI is a single pre-built C# Native AOT binary, dynamically
  # linked against glibc + libgcc and built outside Nix. NixOS stubs
  # /lib64/ld-linux-x86-64.so.2, so a bare store copy cannot run: we patch
  # the interpreter and RPATH to the store copies of glibc + libgcc (see
  # fixupPhase below).
  #
  # Pinned to a specific version + sha256 (this reverses the old
  # bootstrap + `unity self-update` model — see
  # docs/adr/0003-unity-cli-replaces-hub.md). To update: bump `version` and
  # `sha256` (from https://public-cdn.cloud.unity3d.com/hub/prod/cli/latest-beta.json)
  # and rebuild.
  unityCli = pkgs.stdenvNoCC.mkDerivation rec {
    pname = "unity-cli";
    version = "1.0.0-beta.14";

    src = pkgs.fetchurl {
      url = "https://public-cdn.cloud.unity3d.com/hub/prod/cli/${version}/unity-linux-x64";
      sha256 = "d9a2c1716ce723b970898f7f40adc09cceee04e84ce2f1f1638f07ac3e9898aa";
    };

    dontConfigure = true;
    dontBuild = true;
    # src is a single pre-built binary (not an archive) — skip unpacking so
    # $src is the file itself.
    dontUnpack = true;

    nativeBuildInputs = [pkgs.patchelf];

    installPhase = ''
      install -Dm755 "$src" "$out/bin/unity"
    '';

    # Make the pre-built binary runnable on NixOS: point its interpreter and
    # RPATH at the store's glibc + libgcc (the system /lib64 loader is a stub
    # that refuses generic dynamically-linked binaries).
    fixupPhase = ''
      ${pkgs.patchelf}/bin/patchelf \
        --set-interpreter ${pkgs.glibc}/lib/ld-linux-x86-64.so.2 \
        --set-rpath "${pkgs.glibc}/lib:${pkgs.glibc}/lib64:${pkgs.libgcc}/lib" \
        "$out/bin/unity"
    '';

    meta = with lib; {
      description = "Unity command-line interface (official)";
      homepage = "https://unity.com";
      license = licenses.unfree;
      platforms = ["x86_64-linux"];
      mainProgram = "unity";
    };
  };
in {
  # Store-provided, so `unity` is on PATH like any other home package — no
  # ~/.local/bin PATH entry or activation-hook bootstrap is needed.
  home.packages = [unityCli];
}
