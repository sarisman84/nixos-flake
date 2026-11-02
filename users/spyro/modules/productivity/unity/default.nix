{ pkgs, lib, ... }:

let
  # The self-contained unity package (CLI + Editor NixOS support). See
  # ./package.nix for the derivation; it is host-agnostic (the Editor version
  # and the active NVIDIA Vulkan ICD are discovered at runtime).
  unityCli = (import ./package.nix) { inherit pkgs lib; };
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
