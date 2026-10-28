# Research: QEMU test loop for the ISO install

## Ticket
Research: QEMU test loop for the ISO — [`#66`](https://github.com/sarisman84/nixos-flake/issues/66)

## Goal
Verify the headless installer ISO installs `zodiac` correctly end-to-end in QEMU on `two-b` (virtualization enabled, `/dev/kvm` present) before any bare-metal run.

## Environment
- Host: `two-b`, x86_64-linux, KVM enabled (`/dev/kvm` exists)
- `qemu-system-x86_64` and `qemu-img` are **not** currently in PATH on this shell — they must be made available (e.g. `nix shell nixpkgs#qemu_full` or added to the devShell / host packages) before the QEMU proof can run.

## Test loop (two stages)

### Stage 1 — Install (ISO + blank disk)

1. Create a blank target disk image:
   ```bash
   qemu-img create -f qcow2 zodiac-disk.qcow2 50G
   ```

2. Boot the installer ISO with the blank disk attached (UEFI via OVMF):
   ```bash
   qemu-system-x86_64 \
     -enable-kvm -cpu host -m 4G -smp 2 \
     -bios "$(nix-build '<nixpkgs>' -A pkgs.OVMF.fd --no-out-link)/FV/OVMF.fd" \
     -cdrom <installer.iso> -boot order=d \
     -drive file=zodiac-disk.qcow2,format=qcow2 \
     -netdev user,id=net0,net=192.168.100.0/24,dhcpstart=192.168.100.9 \
     -device virtio-net-pci,netdev=net0 \
     -nographic -serial chardev:stdio
   ```

3. From the installer (reached over the serial console or SSH once networking is up), run the unattended install:
   - disko formats `/dev/vda` (GPT + ESP + btrfs root) and mounts it
   - `nixos-install --flake <flake>#zodiac --root /mnt` (or disko-install in one step)
   - Reboot

### Stage 2 — Verify (installed disk alone)

4. Boot the installed disk image without the ISO:
   ```bash
   qemu-system-x86_64 \
     -enable-kvm -cpu host -m 4G -smp 2 \
     -bios "$(nix-build '<nixpkgs>' -A pkgs.OVMF.fd --no-out-link)/FV/OVMF.fd" \
     -drive file=zodiac-disk.qcow2,format=qcow2 \
     -netdev user,id=net0,net=192.168.100.0/24,dhcpstart=192.168.100.9,hostfwd=tcp::2222-:22 \
     -device virtio-net-pci,netdev=net0 \
     -nographic -serial chardev:stdio
   ```

5. Confirm over SSH (`ssh -p 2222 localhost` or `nixos@192.168.100.9`):
   - System boots to a login prompt / SSH is reachable
   - `zodiac` is the hostname, btrfs root mounted, EFI partition present
   - Firewall + SSH defaults match the base server shape

## Key QEMU flags
| Flag | Purpose |
|------|---------|
| `-enable-kvm -cpu host` | Use KVM acceleration (requires `/dev/kvm`) |
| `-bios .../OVMF.fd` | UEFI firmware so EFI boot works (installer + installed system) |
| `-cdrom <iso> -boot order=d` | Boot from the installer ISO (stage 1 only) |
| `-drive file=<img>,format=qcow2` | The target disk to install onto (stage 1) / boot from (stage 2) |
| `-netdev user,hostfwd=tcp::2222-:22` | User-mode networking with SSH port forward (stage 2) |
| `-device virtio-net-pci` | Virtio NIC, gets DHCP from QEMU's user network |
| `-nographic -serial chardev:stdio` | Headless, serial console on stdio (no GUI needed) |

## Automation
For a fully non-interactive proof, drive the install over the serial console with an `expect`-like script, or pre-bake an unattended install script on the ISO (disko-install) so Stage 1 needs no manual input. The VM's QEMU process runs outside the Nix sandbox, so networking is unrestricted.

## Exit criteria for #71 (QEMU install proof)
- ISO builds cleanly from the flake (`nix build` / `nix flake check`)
- Stage 1 installs `zodiac` to the blank disk without console input
- Stage 2 boots the installed disk and is reachable over SSH
- Installed system matches base-server shape: SSH + firewall, btrfs root, EFI boot

## Sources
- NixOS Wiki QEMU — https://wiki.nixos.org/wiki/QEMU (OVMF, qemu packages)
- nix.dev "NixOS virtual machines" — https://nix.dev/tutorials/nixos/nixos-configuration-on-vm.html (`run-nixos-vm`, `-nographic`)
- tfc/nixos-offline-installer QEMU test — https://github.com/tfc/nixos-offline-installer (qemu-img + OVMF + ISO boot pattern)
- l-lin.github.io "installing NixOS on KVM/QEMU" — qemu-system-x86_64 with `-cdrom`, `-boot order=d`, `-drive file=`
