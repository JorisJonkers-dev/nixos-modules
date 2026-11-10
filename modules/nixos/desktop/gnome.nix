{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.platformBlueprints.desktop.gnome;

  # pygobject3 is all the watcher needs on top of the interpreter: it talks to
  # Mutter over the session bus.
  python = pkgs.python3.withPackages (ps: [ps.pygobject3]);

  # Watches for a monitor that Mutter has on while the kernel has it off and
  # applies the fastest mode the kernel still accepts. See display-rescue.py.
  watcher = pkgs.writeShellApplication {
    name = "display-rescue";
    runtimeInputs = [pkgs.libnotify];
    text = ''
      export GI_TYPELIB_PATH=${lib.makeSearchPath "lib/girepository-1.0" [pkgs.glib.out pkgs.gobject-introspection]}
      exec ${python}/bin/python3 -u ${./display-rescue.py}
    '';
  };
in {
  options.platformBlueprints.desktop.gnome = {
    enable = lib.mkEnableOption "GNOME desktop: GDM, PipeWire, NetworkManager, fonts, keyring and AppImage support";

    displayRescue.enable = lib.mkEnableOption "a user service that relights a monitor left dark after suspend, for displays behind adapters that do not come back on their own";
  };

  # Graphics userspace (Mesa, 32-bit graphics, firmware, render group) belongs
  # to a GPU role and is deliberately not repeated here; this module covers the
  # GNOME session, the audio stack and the desktop plumbing only.
  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      services.desktopManager.gnome.enable = lib.mkDefault true;

      # GDM is the display manager; it runs Wayland sessions by default, so no
      # X-server base is pulled in.
      services.displayManager.gdm.enable = lib.mkDefault true;

      # PipeWire is the single audio server (the PulseAudio and JACK
      # replacement). mkDefault sits on each value, not on the whole set: a
      # host that sets any other pipewire option would otherwise discard all
      # of these defaults, enable included.
      services.pulseaudio.enable = lib.mkDefault false;
      services.pipewire = {
        enable = lib.mkDefault true;
        alsa = {
          enable = lib.mkDefault true;
          # 32-bit clients (Steam's runtime and many native 32-bit games) link
          # against libasound in 32-bit form; without it they fail to open the
          # output device.
          support32Bit = lib.mkDefault true;
        };
        # Compatibility layer so PulseAudio-only clients keep working.
        pulse.enable = lib.mkDefault true;
      };

      # Realtime scheduling for the audio threads PipeWire and its JACK clients
      # create; without it they run at normal priority and drop out under load.
      security.rtkit.enable = lib.mkDefault true;

      # NetworkManager is on so Settings > Network works (connection editing,
      # Wi-Fi). Its unmanaged interfaces, DNS handling and the DHCP client stay
      # with the consumer: a host with static interfaces or its own resolver
      # must not have those decided here.
      networking.networkmanager.enable = lib.mkDefault true;

      programs.firefox.enable = lib.mkDefault true;

      # The session keyring backs the Secret Service, which applications use
      # for their own credentials.
      services.gnome.gnome-keyring.enable = true;

      # The default font set covers the UI and the documents a desktop opens; a
      # host that wants a specific family adds it on top.
      fonts.enableDefaultPackages = true;

      programs.appimage = {
        enable = true;
        binfmt = true;
        # Libraries the default FHS env lacks. Recomp Launcher (a Tauri /
        # WebKitGTK AppImage) links libgpg-error, libcom_err and libgmp
        # without bundling them. e2fsprogs provides libcom_err.
        package = pkgs.appimage-run.override {
          extraPkgs = ps: [ps.libgpg-error ps.e2fsprogs ps.gmp];
        };
      };
    }

    (lib.mkIf cfg.displayRescue.enable {
      # A user service, not a system one: it needs the session bus and the
      # user's own Mutter instance, and it must die with the session.
      systemd.user.services.display-rescue = {
        description = "Bring back monitors that stay dark after a suspend or screen blank";
        wantedBy = ["graphical-session.target"];
        partOf = ["graphical-session.target"];
        after = ["graphical-session.target"];
        serviceConfig = {
          ExecStart = lib.getExe watcher;
          Restart = "on-failure";
          RestartSec = 5;
        };
      };
    })
  ]);
}
