{ config, lib, pkgs, ... }:

{
  # Enable OpenGL/Vulkan
  hardware.graphics.enable = true;

  # Load Nvidia Drivers
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = true;
    # Use proprietary driver (open = false)
    open = false; 
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };
}
