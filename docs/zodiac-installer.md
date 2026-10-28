# Zodiac installer: build and test

How to build the bootable installer ISO for the headless `zodiac` server (a flake output of this repo) and how to prove it works in QEMU before any bare-metal run. The QEMU proof is the gate for the bare-metal install ([#74](https://github.com/sarisman84/nixos-flake/issues/74)).

## Table of contents

- [Prerequisites](#prerequisites)
- [Building the ISO](#building-the-iso)
- [QEMU install proof](#qemu-install-proof)
  - [Setup](#setup)
  - [Stage 1 — install](#stage-1--install)
  - [Stage 2 — verify](#stage-2--verify)
- [Verification checklist](#verification-checklist)
- [Troubleshooting](#troubleshooting)
- [Bare-metal notes](#bare-metal-notes)

## Prerequisites

- **Build machine:** Nix with flakes enabled (`nix.settings.experimental-features = [ "nix-command" "flakes" ]`), or the repo devShell (`nix develop .`).
- **QEMU test host:** KVM (`/dev/kvm` present) and `qemu-system-x86_64` + `qemu-img` in PATH. `qemu_full` is in the user environment via Home Manager (`users/spyro/modules/general.nix`); otherwise `nix shell nixpkgs#qemu_full`.
- **A flake ref containing the `zodiac` host entry** — currently the `feature/zodiac-host-entry` branch.
- **The test SSH key** baked into the ISO and the installed system: `/tmp/opencode/zodiac-test-key` (ed25519).

## Building the ISO

```bash
nix flake check
nix build .#nixosConfigurations.zodiac-installer.config.system.build.isoImage
```

The build output is a directory at `result`; the ISO file itself is `result/iso/*.iso` (~1.5 GB). What it contains:

- the minimal NixOS installer environment (`installation-cd-minimal.nix`),
- headless SSH with the test key baked into root's `authorized_keys`,
- `git` + `disko` and Nix flakes support, so the install is driven entirely over SSH,
- `btrfs` / `vfat` / `xfs` filesystem support for the target disk.

The ISO does **not** carry the disko config — it is copied into the VM at test time (see Stage 1).

> **Temporary:** until [#73](https://github.com/sarisman84/nixos-flake/issues/73) lands, the ISO also enables password auth (`PasswordAuthentication`, `PermitRootLogin = "yes"`, root password `zodiac`) for proof convenience. The shipped installer will be key-only.

## QEMU install proof

A QEMU VM stands in for the bare-metal server: the installer is identical, only the target hardware is substituted (a virtual disk for the real one). Two stages — install, then verify.

### Setup

Create a blank target disk (50G is plenty for the closure + store):

```bash
qemu-img create -f qcow2 zodiac-disk.qcow2 50G
```

### Stage 1 — install

Boot the ISO with the blank disk attached (UEFI via OVMF, virtio NIC, serial console on stdio):

```bash
qemu-system-x86_64 \
  -enable-kvm -cpu host -m 16G -smp 4 \
  -bios "$(nix eval --raw nixpkgs#OVMF.fd.outPath)/FV/OVMF.fd" \
  -cdrom result/iso/*.iso -boot order=d \
  -drive file=zodiac-disk.qcow2,format=qcow2 \
  -netdev user,id=net0,net=192.168.100.0/24,dhcpstart=192.168.100.9 \
  -device virtio-net-pci,netdev=net0 \
  -nographic -serial chardev:stdio
```

16G RAM is needed to stage the host closure during install; an undersized VM fails part-way through.

Once the installer boots, it gets `192.168.100.9` from QEMU's user network. From the host:

```bash
# 1. Wait for SSH, then copy the disko config in
ssh -i /tmp/opencode/zodiac-test-key root@192.168.100.9
scp -i /tmp/opencode/zodiac-test-key \
  installers/zodiac-installer/disko-config.nix root@192.168.100.9:/root/

# 2. On the VM: partition + format + mount (GPT + 512M EFI vfat + btrfs root, labelled)
disko --mode destroy,format,mount --yes-wipe-all-disks /root/disko-config.nix

# 3. On the VM: install the host closure into /mnt (where disko mounted it)
git clone --depth 1 --branch feature/zodiac-host-entry \
  https://github.com/sarisman84/nixos-flake.git /root/flake
nixos-install --flake /root/flake#zodiac

# 4. Reboot
reboot
```

### Stage 2 — verify

Power the VM off, then boot the installed disk **without** the ISO, with an SSH port forward:

```bash
qemu-system-x86_64 \
  -enable-kvm -cpu host -m 16G -smp 4 \
  -bios "$(nix eval --raw nixpkgs#OVMF.fd.outPath)/FV/OVMF.fd" \
  -drive file=zodiac-disk.qcow2,format=qcow2 \
  -netdev user,id=net0,net=192.168.100.0/24,dhcpstart=192.168.100.9,hostfwd=tcp::2222-:22 \
  -device virtio-net-pci,netdev=net0 \
  -nographic -serial chardev:stdio
```

Connect and run the checklist:

```bash
ssh -i /tmp/opencode/zodiac-test-key -p 2222 root@localhost
```

## Verification checklist

The proof passes when all of these hold on the installed system:

- [ ] Boots from disk to a healthy multi-user state (no emergency shell)
- [ ] `hostname` is `zodiac`
- [ ] Disk scheme: GPT + 512M EFI (vfat, label `zodiac-boot`) + btrfs root (label `zodiac-root`) — `lsblk -f`
- [ ] Obtained a DHCP address and is reachable over SSH
- [ ] SSH is key-only (password auth refused)
- [ ] Firewall allows only SSH — `nft list ruleset`

## Troubleshooting

- **`ssh` hangs with "Connection timed out during banner exchange"** — the guest's virtio NIC never came up (SLIRP accepts the forward, but the guest has no IP). Cause: missing virtio kernel modules in the initrd. Fix: the host config imports the NixOS `qemu-guest.nix` profile (`hosts/zodiac/qemu.nix`). This was initially misdiagnosed as a QEMU/SLIRP bug — it is not.
- **Installed system drops to an emergency shell, ~90s hang on first boot** — the btrfs root or EFI partition is missing its label, so `/dev/disk/by-label/zodiac-root` never resolves. Cause: the disko config must set the labels via `extraArgs` (`-n` for vfat, `-L` for btrfs); they must match `hosts/zodiac/hardware-configuration.nix`.
- **Install fails part-way staging the closure** — the VM is undersized. Raise `-m` (16G works).
- **`nix flake check` can't see new files** — it evaluates from a git-derived store path; `git add`/commit untracked files first.

## Bare-metal notes

- The installer and host config are hardware-agnostic; the same ISO and flake ref are used. Only the target disk differs.
- Before running disko on the real server, point `device` in the disko config at the real disk (e.g. `/dev/nvme0n1` instead of `/dev/sda`).
- The serial console (`console=ttyS0,115200n8`) is the fallback observation channel if the network is unreachable.
- The QEMU proof is the passing precondition for the bare-metal run; the run itself is tracked in [#74](https://github.com/sarisman84/nixos-flake/issues/74).
