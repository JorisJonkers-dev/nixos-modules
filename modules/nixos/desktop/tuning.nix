{
  config,
  lib,
  ...
}: let
  cfg = config.platformBlueprints.desktop.tuning;
in {
  options.platformBlueprints.desktop.tuning = {
    enable = lib.mkEnableOption "desktop and laptop tuning: zram, sysctl, memory caps and I/O schedulers";

    preset = lib.mkOption {
      type = lib.types.enum ["desktop" "laptop"];
      description = "desktop keeps the audio codec powered and caps zram at 16 GiB; laptop keeps audio power saving and sizes zram at half of RAM";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      # Compressed swap in RAM (zstd) absorbs memory spikes from browsers,
      # build jobs and virtual machines, and is far cheaper than paging to a
      # disk.
      #
      # To empty it by hand, never use a bare swapoff/swapon: swapoff makes
      # systemd reset the device and swapon then fails with "read swap header
      # failed", leaving the machine with no swap.
      zramSwap = {
        enable = true;
        algorithm = "zstd";
        priority = 100;
      };

      # Values from CachyOS's sysctl defaults, each overridable per host via
      # mkDefault so a machine can tune around them.
      boot.kernel.sysctl = {
        # CachyOS ships 100 (anonymous pages and page cache cost the same to
        # reclaim). In practice that parked 11 GiB of idle desktop apps in
        # zram after one spike, and every tab switch then paid to decompress
        # them. 30 makes the kernel drop page cache first and swap only under
        # real pressure.
        "vm.swappiness" = lib.mkDefault 30;

        # Below the default of 100, the kernel is less eager to reclaim the
        # directory and inode cache. That keeps application and build-tree
        # file lookups warm across load and unload spikes (do not set it to 0).
        "vm.vfs_cache_pressure" = lib.mkDefault 50;

        # Absolute cap (256 MiB) on dirty page cache before a writing process
        # must flush itself, so a cache or build write burst cannot park a
        # large share of RAM in unwritten data and then stall on one flush.
        "vm.dirty_bytes" = lib.mkDefault 268435456;

        # Background writeback starts at 64 MiB, well before the cap above.
        "vm.dirty_background_bytes" = lib.mkDefault 67108864;

        # Flusher threads wake every 15 s (value is in centiseconds) instead of
        # the default 5 s: fewer wakeups, and the byte caps above still bound
        # how much dirty data can pile up.
        "vm.dirty_writeback_centisecs" = lib.mkDefault 1500;

        # Swap readahead assumes a seek on disk; zram has none, and readahead
        # just decompresses pages that are never touched.
        "vm.page-cluster" = lib.mkDefault 0;

        # The NMI watchdog burns a hardware perf counter for a hang detector a
        # desktop gains nothing from; CachyOS disables it.
        "kernel.nmi_watchdog" = lib.mkDefault 0;

        # Enable all SysRq functions: safely sync and reboot after a hang
        # (CachyOS). NixOS has no boot.kernel.sysrq option in this nixpkgs, so
        # the sysctl is the correct surface.
        "kernel.sysrq" = lib.mkDefault 1;
      };

      # nix-daemon peaked at 28.8 GiB during a large rebuild. Fewer parallel
      # jobs keep the peak down; the cgroup caps below throttle, and at worst
      # fail, a build rather than the desktop.
      nix.settings.max-jobs = lib.mkDefault 4;

      systemd = {
        # Memory caps, so one runaway workload cannot push the whole desktop
        # into swap and then into a global OOM kill. A python process started
        # from a terminal once reached 21.5 GiB, filled zram and the kernel OOM
        # killer fired system-wide. With these caps the offender is throttled
        # and, at the hard limit, killed inside its own cgroup while the rest
        # of the session keeps running.
        #
        # Each GNOME terminal tab runs in its own transient vte-spawn-<id>.scope;
        # a "vte-spawn-.scope" drop-in applies to all.
        user.units."vte-spawn-.scope" = {
          overrideStrategy = "asDropin";
          text = ''
            [Scope]
            MemoryHigh=45%
            MemoryMax=60%
            MemorySwapMax=2G
          '';
        };

        services.nix-daemon.serviceConfig = {
          MemoryHigh = lib.mkDefault "50%";
          MemoryMax = lib.mkDefault "70%";
          MemorySwapMax = lib.mkDefault "4G";
        };

        # Transparent huge pages, as CachyOS ships them. defrag=defer+madvise
        # avoids stalling a page fault on direct compaction, except for memory
        # an application asked to be huge. The THP shrinker setting
        # (max_ptes_none 409, default 511) splits any huge page that is more
        # than 80% zero-filled, which keeps memory use close to THP=madvise
        # while keeping most of the speedup of THP=always. The shrinker needs
        # kernel 6.12+.
        tmpfiles.rules = [
          "w! /sys/kernel/mm/transparent_hugepage/defrag - - - - defer+madvise"
          "w! /sys/kernel/mm/transparent_hugepage/khugepaged/max_ptes_none - - - - 409"
        ];
      };

      # The rules key off the queue/rotational flag rather than a device name,
      # so a machine that gains an NVMe later picks kyber without touching this
      # file. CachyOS defaults: bfq for seek-bound HDDs, mq-deadline for SATA/
      # MMC SSDs, kyber for NVMe.
      services.udev.extraRules = ''
        # HDD
        ACTION=="add|change", KERNEL=="sd[a-z]*", ATTR{queue/rotational}=="1", \
            ATTR{queue/scheduler}="bfq"

        # SSD
        ACTION=="add|change", KERNEL=="sd[a-z]*|mmcblk[0-9]*", ATTR{queue/rotational}=="0", \
            ATTR{queue/scheduler}="mq-deadline"

        # NVMe SSD
        ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/rotational}=="0", \
            ATTR{queue/scheduler}="kyber"
      '';
    }

    (lib.mkIf (cfg.preset == "desktop") {
      # Bazzite caps the device at min(RAM/2, 16 GiB); 16 GiB is that ceiling
      # for a machine with 32 GiB or more.
      zramSwap.memoryMax = 17179869184;

      # Onboard HDA power saving clicks and pops on a desktop when the codec
      # powers down between sounds; disable controller and codec power
      # management for uninterrupted audio. A laptop keeps the power saving:
      # there the battery matters more than the occasional click.
      boot.extraModprobeConfig = ''
        options snd_hda_intel power_save=0 power_save_controller=N
      '';
    })

    (lib.mkIf (cfg.preset == "laptop") {
      # Half of RAM with no fixed cap: a laptop with 64 GiB gets 32 GiB of
      # compressed swap instead of the desktop's 16 GiB ceiling.
      zramSwap.memoryPercent = 50;
    })
  ]);
}
