{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.platformBlueprints.roles.gpuAmd;

  rocmSmiWrapped = pkgs.symlinkJoin {
    name = "rocm-smi-wrapped";
    paths = [pkgs.rocmPackages.rocm-smi];
    nativeBuildInputs = [pkgs.makeWrapper];
    postBuild = ''
      wrapProgram $out/bin/rocm-smi \
        --prefix LD_LIBRARY_PATH : ${pkgs.libdrm}/lib
    '';
  };

  # The ROCm inspection tools belong to the compute stack, so they are not part
  # of the graphics package list.
  rocmTools = [
    rocmSmiWrapped
    pkgs.rocmPackages.rocminfo
  ];

  # The graphics stack pulls in amdgpu- and amdvlk; hip and rocm only arrive
  # with the compute stack.
  unfreeGraphicsPackages = [
    "amdgpu-"
    "amdvlk"
  ];
  # Prefixes: the compute stack is many packages (rocminfo, rocm-smi, hipblas).
  unfreeRocmPackages = [
    "hip*"
    "rocm*"
  ];
in {
  imports = [
    ./gpu-utility.nix
    ../unfree.nix
  ];

  options.platformBlueprints.roles.gpuAmd = {
    enable = lib.mkEnableOption "AMD GPU host role with Mesa, ROCm, and scheduler labels";

    mode = lib.mkOption {
      type = lib.types.enum ["apu" "discrete"];
      description = "apu for an integrated GPU (graphics stack only), discrete for a dedicated card (adds ROCm compute, overdrive and LACT)";
    };

    rocm.enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.mode == "discrete";
      defaultText = "config.platformBlueprints.roles.gpuAmd.mode == \"discrete\"";
      description = "Install the ROCm compute stack: kfd access, the CLR ICD and the ROCm inspection tools.";
    };

    overdrive.enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.mode == "discrete";
      defaultText = "config.platformBlueprints.roles.gpuAmd.mode == \"discrete\"";
      description = "Enable the amdgpu overdrive interface for clock and voltage control.";
    };

    lact.enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.mode == "discrete";
      defaultText = "config.platformBlueprints.roles.gpuAmd.mode == \"discrete\"";
      description = "Enable LACT, the AMD GPU fan and clock control daemon.";
    };

    enable32BitGraphics = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable 32-bit Mesa userspace for Vulkan and OpenGL workloads.";
    };

    enableRedistributableFirmware = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable redistributable firmware blobs required by AMD GPUs.";
    };

    allowUnfreePackages = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Allow AMD GPU and ROCm package names that nixpkgs marks unfree.";
    };

    installUtilities = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install AMD GPU and ROCm inspection tools.";
    };

    packages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = with pkgs; [
        clinfo
        libdrm
        libva-utils
        pciutils
        radeontop
        vulkan-tools
      ];
      description = "AMD GPU utility packages installed when installUtilities is true.";
    };

    rocmRuntimeDirectory = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/var/lib/rocm";
      description = "Optional runtime directory created with render-group ownership for ROCm workloads.";
    };

    renderGroup = lib.mkOption {
      type = lib.types.str;
      default = "render";
      description = "Group that should own ROCm runtime state and /dev/kfd.";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      boot.initrd.kernelModules = ["amdgpu"];
      boot.kernelModules = [
        "amdgpu"
        "kvm-amd"
      ];

      hardware.enableRedistributableFirmware = cfg.enableRedistributableFirmware;
      hardware.firmware = [pkgs.linux-firmware];
      hardware.graphics = {
        enable = true;
        enable32Bit = cfg.enable32BitGraphics;
        extraPackages = with pkgs; [
          libva
          libvdpau-va-gl
          mesa
        ];
        extraPackages32 = lib.mkIf cfg.enable32BitGraphics (with pkgs.pkgsi686Linux; [
          mesa
        ]);
      };

      hardware.amdgpu.overdrive.enable = cfg.overdrive.enable;
      services.lact.enable = cfg.lact.enable;

      platformBlueprints.roles.gpuUtility = {
        enable = true;
        gpuVendors = ["amd"];
        installUtilities = false;
      };

      assertions = [
        {
          assertion = config.hardware.graphics.enable;
          message = "platformBlueprints.roles.gpuAmd requires hardware.graphics.enable.";
        }
      ];
    }

    (lib.mkIf cfg.allowUnfreePackages {
      platformBlueprints.unfree.packages = unfreeGraphicsPackages;
    })

    (lib.mkIf (cfg.allowUnfreePackages && cfg.rocm.enable) {
      platformBlueprints.unfree.packages = unfreeRocmPackages;
    })

    (lib.mkIf cfg.installUtilities {
      environment.systemPackages = cfg.packages;
    })

    (lib.mkIf (cfg.installUtilities && cfg.rocm.enable) {
      environment.systemPackages = rocmTools;
    })

    (lib.mkIf cfg.rocm.enable {
      # kfd is the compute queue device; ROCm workloads cannot open the GPU
      # without it.
      services.udev.extraRules = ''
        KERNEL=="kfd", GROUP="${cfg.renderGroup}", MODE="0660"
      '';

      hardware.graphics.extraPackages = [pkgs.rocmPackages.clr.icd];
    })

    (lib.mkIf (cfg.rocm.enable && cfg.rocmRuntimeDirectory != null) {
      systemd.tmpfiles.rules = [
        "d ${cfg.rocmRuntimeDirectory} 0755 root ${cfg.renderGroup} - -"
      ];
    })
  ]);
}
