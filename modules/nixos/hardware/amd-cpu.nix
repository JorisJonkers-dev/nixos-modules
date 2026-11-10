{
  config,
  lib,
  ...
}: let
  cfg = config.platformBlueprints.hardware.amdCpu;
in {
  options.platformBlueprints.hardware.amdCpu = {
    enable = lib.mkEnableOption "AMD CPU support: microcode updates, the amd_pstate driver and KVM";
  };

  config = lib.mkIf cfg.enable {
    # Microcode is a redistributable blob, so the update is only meaningful
    # when the firmware channel is open. Defaulting it to the merged value
    # keeps the two in step without overriding a host that already decided.
    hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
    hardware.enableRedistributableFirmware = lib.mkDefault true;

    # amd_pstate=active selects the CPPC driver instead of acpi-cpufreq, which
    # is what gives power-profiles-daemon more than two profiles to offer.
    boot.kernelParams = ["amd_pstate=active"];
    boot.kernelModules = ["kvm-amd"];
  };
}
