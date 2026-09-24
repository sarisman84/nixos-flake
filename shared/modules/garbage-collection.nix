# Shared NixOS module: automatic Nix store garbage collection.
#
# Applied to every host by builder.nix. The per-host settings arrive as the
# `nixGC` specialArg (sourced from each host's host.nix `nixGC` block) — the
# same threading used for sharedImports/inputs/pkgsStable — because flags
# declared in host.nix are not visible as NixOS `config.*` options.
#
# When `nixGC.enable` is true, installs the `nix-gc` service + timer and sets
# the retention window. `--delete-older-than` (not a bare `--delete-older-than
# N` with no value) keeps recent generations available for rollback, which
# matters since the timer runs unattended.
{
  nixGC,
  lib,
  ...
}:
{
  config = lib.mkIf nixGC.enable {
    nix.gc = {
      automatic = true; # enables nix-gc.service + the systemd timer
      dates = nixGC.dates; # timer schedule (cron expression)
      options = "--delete-older-than ${nixGC.deleteOlderThan}"; # retention window
    };
    # Dedupe identical store paths on every GC run.
    nix.settings.auto-optimise-store = true;
  };
}
