# Serverspace vStack server (bhyve). IPv4 only; the platform injects a static
# configuration into its images, so it is taken from machine.json, recorded by
# `just install` from the stock image.
{ ... }:
{
  mailserver.machine.network.method = "static";
  boot.initrd.availableKernelModules = [ "nvme" ];
}
