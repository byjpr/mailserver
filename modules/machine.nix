# Disk layout, boot loader and networking for a KVM virtual server. The
# provider-specific parts (disk device, how the public addresses are
# configured) come from providers/<name>.nix, selected by settings.provider.
{
  config,
  lib,
  modulesPath,
  ctx,
  ...
}:
let
  cfg = config.mailserver.machine;
  net = cfg.network;

  # Facts about the actual server (disk device, addresses), recorded by
  # `just install` in machine.json. null before the first install.
  machine = ctx.machine;

  staticAddress = lib.types.submodule {
    options = {
      address = lib.mkOption { type = lib.types.str; };
      prefixLength = lib.mkOption { type = lib.types.int; };
      gateway = lib.mkOption { type = lib.types.str; };
    };
  };
in
{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  options.mailserver.machine = {
    disk = lib.mkOption {
      type = lib.types.str;
      default = if machine != null then machine.disk else "/dev/vda";
      description = "Disk that disko partitions on install (wiped!).";
    };

    network = {
      method = lib.mkOption {
        type = lib.types.enum [
          "dhcp"
          "static"
          "cloud-init"
        ];
        description = ''
          How the public addresses are configured:
          - dhcp: DHCPv4 plus IPv6 router advertisements / DHCPv6
          - static: fixed addresses from settings.server.network
          - cloud-init: read from the provider's metadata service
        '';
      };
      cloudInitDatasource = lib.mkOption {
        type = lib.types.str;
        default = "";
      };
      ipv4 = lib.mkOption {
        type = lib.types.nullOr staticAddress;
        default = if machine != null && net.method == "static" then machine.ipv4 else null;
        description = "Static IPv4 configuration (method = static).";
      };
      ipv6 = lib.mkOption {
        type = lib.types.nullOr staticAddress;
        default = if machine != null && net.method == "static" then machine.ipv6 else null;
        description = ''
          Static IPv6 configuration (method = static). Can also be set on top
          of DHCP for providers that route a /64 without announcing it.
        '';
      };
    };
  };

  config = lib.mkMerge [
    {
      # Hybrid GPT so the server boots whether the hypervisor starts it via
      # BIOS or UEFI. Applied by nixos-anywhere on first install.
      disko.devices.disk.main = {
        type = "disk";
        device = cfg.disk;
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
          "ahci"
          "sd_mod"
          "sr_mod"
        ];
        kernelParams = [ "console=ttyS0" ];
        growPartition = true;
      };

      networking.useDHCP = false;
      networking.useNetworkd = true;
      systemd.network.enable = true;

      # 1-2 GB of RAM is tight during upgrades; compressed swap in RAM avoids
      # the OOM killer without wearing the disk.
      zramSwap = {
        enable = true;
        memoryPercent = 50;
      };
    }

    (lib.mkIf (net.method == "dhcp" || net.method == "static") {
      systemd.network.networks."10-wan" = {
        # Static addresses go on the NIC recorded at install time; with DHCP,
        # every Ethernet NIC (UpCloud attaches one NIC per address).
        matchConfig =
          if net.method == "static" && machine != null && (machine.mac or null) != null then
            { MACAddress = machine.mac; }
          else
            { Type = "ether"; };
        networkConfig = {
          DHCP = if net.method == "dhcp" then "yes" else "no";
          IPv6AcceptRA = net.method == "dhcp";
          IPv6PrivacyExtensions = false;
        };
        # With DHCP, also add the provider-assigned IPv6 address (the one with
        # reverse DNS, which Postfix sends from) in case DHCPv6/SLAAC picks
        # another one.
        address =
          lib.optional (
            net.method == "dhcp" && machine != null && (machine.publicIPv6 or "") != ""
          ) "${machine.publicIPv6}/128"
          ++ lib.optional (net.ipv4 != null) "${net.ipv4.address}/${toString net.ipv4.prefixLength}"
          ++ lib.optional (net.ipv6 != null) "${net.ipv6.address}/${toString net.ipv6.prefixLength}";
        routes =
          # GatewayOnLink: several providers use a gateway outside the
          # server's own subnet (or a /32 address).
          lib.optional (net.ipv4 != null) {
            Gateway = net.ipv4.gateway;
            GatewayOnLink = true;
          }
          ++ lib.optional (net.ipv6 != null) {
            Gateway = net.ipv6.gateway;
            GatewayOnLink = true;
          };
        # The local resolver (Knot Resolver) answers all lookups.
        dhcpV4Config.UseDNS = false;
        dhcpV6Config.UseDNS = false;
        ipv6AcceptRAConfig.UseDNS = false;
      };
    })

    (lib.mkIf (net.method == "cloud-init") {
      # cloud-init only writes the systemd-networkd configuration from the
      # provider's metadata; every other module is turned off so it can never
      # touch users, SSH keys or host keys.
      services.cloud-init = {
        enable = true;
        network.enable = true;
        settings = {
          datasource_list = [ net.cloudInitDatasource ];
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
    })

    {
      assertions = [
        {
          assertion = net.method != "static" || net.ipv4 != null;
          message = "This provider needs a static network configuration from machine.json, which `just install` records. Run `just install` (or write machine.json by hand).";
        }
        {
          assertion = net.method != "cloud-init" || net.cloudInitDatasource != "";
          message = "mailserver.machine.network.cloudInitDatasource must be set for method = cloud-init.";
        }
      ];
    }
  ];
}
