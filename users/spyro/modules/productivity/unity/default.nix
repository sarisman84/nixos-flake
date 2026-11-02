{ pkgs, lib, pkgsStable, ... }:

let
  # The self-contained unity package (CLI + Editor NixOS support). See
  # ./package.nix for the derivation; it is host-agnostic (the Editor version
  # and the active NVIDIA Vulkan ICD are discovered at runtime).
  #
  # libxml2 and icu are pinned to the versions the Editor was built against
  # (its binaries have hard NEEDED deps on libxml2.so.2 and libicu*.so.76,
  # SONAMEs that current nixpkgs no longer provides — libxml2 2.15.x renamed
  # the former to libxml2.so.16, icu 78 the latter to libicu*.so.78).
  #   libxml2: pkgs.libxml2_13.out  (2.13.x, SONAME libxml2.so.2)
  #   icu:     pkgsStable.icu       (76.1, SONAMEs libicu*.so.76)
  unityCli = (import ./package.nix) {
    inherit pkgs lib;
    libxml2 = pkgs.libxml2_13.out;
    icu = pkgsStable.icu;
  };
in
{
  # Store-provided, so `unity` (and the `unity-editor` launcher + patchelf
  # script) are on PATH like any other home package — no ~/.local/bin PATH
  # entry or activation-hook bootstrap is needed.
  home.packages = [ unityCli ];

  # Make the in-place Unity Editor runnable on NixOS: run the package's own
  # idempotent patchelf (it discovers the Editor at runtime and points its
  # binaries at the package's lib/unity-editor-libs). Runs after linkGeneration
  # so the launcher is in place first. Safe to re-run on every deploy — it
  # keeps the RPATHs in sync with the store after a system update, and skips
  # cleanly on a host without the Editor.
  home.activation.unityEditor = lib.hm.dag.entryAfter [ "linkGeneration" ] (
    "run \"${unityCli}/bin/unity-editor-patchelf\""
  );
}
