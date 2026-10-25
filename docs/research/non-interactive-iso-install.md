# Research: non-interactive NixOS ISO install mechanism

## Ticket
Research: non-interactive NixOS ISO install mechanism — [`#65`](https://github.com/sarisman84/nixos-flake/issues/65)

## Goal
Produce a bootable NixOS ISO (a flake output of this repo) that installs a new headless server host entry (`zodiac`) non-interactively — no console, no keyboard, no monitor — proven later in QEMU (`#71`) before bare metal.

## Mechanism (recommended)

**Build the ISO from a flake `nixosConfiguration`.** Since NixOS 25.05 most of `nixos-generators` has been upstreamed into nixpkgs, so the canonical build is:

```bash
nix build .#nixosConfigurations.<iso-name>.config.system.build.isoImage
```

Equivalent legacy form:

```bash
nixos-rebuild build-image --image-variant iso --flake .#<iso-name>
```

The ISO is a NixOS system configuration that imports the installer base module:

```nix
imports = [ "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix" ];
```

(or `installation-cd-base.nix` for a slightly fuller installer environment).

## Unattended / non-interactive install

The disk layout (GPT + EFI + single btrfs root with subvolumes) and the install itself are handled by **disko**:

- `disko.nixosModules.disko` declares `disko.devices.<disk>` with a `gpt` content table, an `EF00` ESP partition (vfat, `/boot`) and a btrfs root partition.
- **disko-install** (`nix-community/disko`) runs disko (destroy/format/mount) then `nixos-install --system <toplevel> --root <mount>` in one step — no console interaction needed.
- The newer `nixos-rebuild build-image --image-variant disko-unattended-install-iso` variant (disko PR #1272) bakes the deployee config into a single unattended-install ISO; disko-install is the more immediately usable path.

### Headless (no console) requirements on the ISO
For a machine reachable only over SSH after install, the ISO must:
- Enable `services.openssh.enable = true`
- Bake in root `openssh.authorizedKeys.keys` (and/or a known `initialPassword`) so the installer can be reached over SSH without a keyboard
- Set `nix.settings.experimental-features = [ "nix-command" "flakes" ]` so flake-based `nixos-install --flake ...` works from the installer environment
- Include `git` (and optionally `disko`) in `environment.systemPackages` for the install flow

### Remote-install alternative
**nixos-anywhere** (`nix-community/nixos-anywhere`) performs the same unattended flow over SSH: it kexecs into a NixOS installer, runs disko + nixos-install, and reboots. It requires the target to be reachable over the network with an installer already booted (USB or netboot), or a kexec-capable kernel. For a truly headless bare-metal commissioning, the local ISO + disko-install path is the better fit.

## Hardware-agnostic considerations
- Target device: single disk, addressed as `/dev/sda` or `/dev/disk/by-id/<...>`; disko supports both.
- Only one disk is pooled (no LVM) per the disk scheme — LVM only if multiple disks are later added.
- UEFI (systemd-boot or GRUB) assumed; BIOS fallback possible via `raw-efi`/`raw` image variants.
- No desktop environment: base server only (SSH + firewall + sane defaults).

## Open questions to resolve in #67 / #68
- Exact disk device path for `zodiac` (hardware unknown until server facts arrive)
- Whether `disko-install` (available now in nixpkgs unstable) vs the not-yet-stable `disko-unattended-install-iso` variant is used
- Where the ISO `nixosConfiguration` lives in the flake (`flake.nix` outputs vs a dedicated `hosts/iso/` entry)

## Sources
- nix-community/disko — https://github.com/nix-community/disko (disko-install, unattended install)
- nix-community/nixos-anywhere — https://github.com/nix-community/nixos-anywhere (remote unattended install)
- chrillefkr/nixos-unattended-installer — https://github.com/chrillefkr/nixos-unattended-installer (systemd-service wrapper on ISO)
- nix-community/disko PR #1272 — `disko-unattended-install-iso` image variant
- nix.dev "Building a bootable ISO image" — https://nix.dev/tutorials/nixos/building-bootable-iso-image.html
- nix-community/nixos-generators README (deprecated, upstreamed into nixpkgs 25.05) — `nixos-rebuild build-image --image-variant iso`
