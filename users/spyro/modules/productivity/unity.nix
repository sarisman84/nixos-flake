{
  pkgs,
  lib,
  config,
  ...
}: let
  homeDir = config.home.homeDirectory;
in {
  # The Unity CLI is deliberately NOT store-pinned: the flake guarantees its
  # presence (the activation hook below), and `unity self-update` keeps it
  # current. A pinned binary would go stale — the official skill warns an
  # outdated CLI fails in confusing ways — and IDE support depends on a
  # recent release. See docs/adr/0003-unity-cli-replaces-hub.md.

  # The install script places the binary in ~/.local/bin, which is not on
  # PATH by default on this system.
  home.sessionVariables.PATH = ":${homeDir}/.local/bin";

  # Bootstrap the CLI on first activation (or after a wiped ~/.local/bin).
  # Idempotent: a no-op while the binary is present. Warns, never fails the
  # deploy — a transient network blip must not break a system switch, and
  # the next activation retries.
  home.activation.unityCliBootstrap = lib.hm.dag.entryAfter ["linkGeneration"] ''
    if [ ! -x "$HOME/.local/bin/unity" ]; then
      echo "unity-cli: installing the Unity CLI..."
      # The install script downloads the binary with a bare `curl`/`wget`
      # from PATH (and may probe glibc via `ldd`), but the activation
      # environment's PATH has neither — so put the store copies on PATH
      # for the script's own runtime.
      export PATH="${pkgs.curl}/bin:${pkgs.glibc}/bin:$PATH"
      if ! ${pkgs.curl}/bin/curl -fsSL https://unity.com/install.sh | ${pkgs.bash}/bin/bash; then
        echo "unity-cli: install failed; \`unity\` is not available. Re-run a deploy, or install manually: curl -fsSL https://unity.com/install.sh | bash" >&2
      fi
    fi
  '';
}
