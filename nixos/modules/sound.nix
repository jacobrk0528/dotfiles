{ config, pkgs, ... }:

{
  # --- Audio (Pipewire) ---
  security.rtkit.enable = true;
  services.pulseaudio.enable = false; # Disable PulseAudio to prevent conflicts

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    wireplumber.enable = true; # Better Bluetooth device management
  };
  
  services.blueman.enable = true; # Bluetooth Manager GUI
}
