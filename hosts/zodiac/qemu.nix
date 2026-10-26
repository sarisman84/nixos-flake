{ modulesPath, lib, ... }:

{
  # Make this configuration testable in QEMU (install proof, ticket #71) while
  # staying hardware-agnostic for the bare-metal `zodiac` server.
  #
  # `qemu-guest.nix` puts the virtio kernel modules (virtio_net, virtio_pci,
  # virtio_blk, ...) into the initrd so the emulated NIC and disk are available
  # from early boot. On bare metal these modules are simply never matched, so
  # this is a no-op there. Without it, a QEMU VM's virtio-net interface can fail
  # to come up, which surfaces as `ssh` hanging with "Connection timed out
  # during banner exchange" (SLIRP accepts the hostfwd but the guest has no IP).
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  # Serial console on ttyS0. Useful on a headless server as a fallback when the
  # network is unreachable, and it is how the QEMU install proof observes the
  # boot (QEMU is started with `-serial file:...` / `-serial mon:stdio`).
  boot.kernelParams = lib.mkAfter [
    "console=ttyS0,115200n8"
  ];
  boot.consoleLogLevel = lib.mkDefault 5;
}
