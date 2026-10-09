# Hardware, disk layout and networking for a DigitalOcean droplet.
{ lib, modulesPath, ... }:
{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  # Disk layout, applied by nixos-anywhere on first install. Hybrid GPT so the
  # droplet boots whether DigitalOcean starts it via BIOS or UEFI.
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/vda";
    content = {
      type = "gpt";
      partitions = {
        bios = {
          size = "1M";
          type = "EF02";
        };
        ESP = {
          size = "512M";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };

  boot = {
    loader.grub = {
      enable = true;
      efiSupport = true;
      efiInstallAsRemovable = true;
    };
    initrd.availableKernelModules = [
      "virtio_pci"
      "virtio_scsi"
      "virtio_blk"
      "virtio_net"
    ];
    kernelParams = [ "console=ttyS0" ];
    growPartition = true;
  };

  # DigitalOcean hands out the public IPv4/IPv6 addresses through its metadata
  # service rather than DHCP/SLAAC. cloud-init reads it and writes the
  # systemd-networkd configuration; every other cloud-init module is turned off
  # so it can never touch users, SSH keys or host keys.
  services.cloud-init = {
    enable = true;
    network.enable = true;
    settings = {
      datasource_list = [ "DigitalOcean" ];
      preserve_hostname = true;
      manage_etc_hosts = false;
      ssh_deletekeys = false;
      ssh_genkeytypes = [ ];
      disable_root = false;
      users = lib.mkForce [ ];
      cloud_init_modules = lib.mkForce [ ];
      cloud_config_modules = lib.mkForce [ ];
      cloud_final_modules = lib.mkForce [ ];
    };
  };
  networking.useDHCP = false;
  networking.useNetworkd = true;

  # Metrics and alerting in the DigitalOcean control panel (CPU, memory, disk).
  services.do-agent.enable = true;

  # 1 GB of RAM is tight during upgrades; compressed swap in RAM avoids the
  # OOM killer without wearing the disk.
  zramSwap = {
    enable = true;
    memoryPercent = 50;
  };
}
