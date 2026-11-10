{
  self,
  agentKitPackages,
}: {
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.platformBlueprints.roles.devWorkstation;
  system = pkgs.stdenv.hostPlatform.system;

  # nixos-modules entries resolve to this flake's own packages, which exist
  # only for the platforms they are built for (kotlin-lsp is x86_64-only), so
  # an entry this flake does not provide for the host is left out rather than
  # failing evaluation on, say, aarch64.
  ownPackages = self.packages.${system} or {};
  resolve = entry:
    if entry.source == "nixos-modules"
    then ownPackages.${entry.attr} or null
    else lib.getAttrFromPath (lib.splitString "." entry.attr) pkgs;
  resolveGroup = group: builtins.filter (pkg: pkg != null) (map resolve (agentKitPackages.${group} or []));

  # The groups agent-kit's registry sorts tools into, each switchable here.
  # core is always installed.
  optionalGroups = ["kubernetes" "latex" "polyglot" "android"];
  enabledGroups = ["core"] ++ builtins.filter (group: cfg.groups.${group}.enable) optionalGroups;

  # One-command entry point for agent-kit's installer. The installer is
  # imperative and interactive on purpose: it signs in to
  # auth.jorisjonkers.dev (password and TOTP), mints a per-device token and
  # stores it in the user's Secret Service, so it cannot run from NixOS
  # activation or a deploy. This wrapper only makes sure the checkout exists
  # and then runs it. Run it once, by hand, on the machine.
  agentKitSetup = pkgs.writeShellApplication {
    name = "agent-kit-setup";
    runtimeInputs = [pkgs.git pkgs.coreutils];
    text = ''
      # ~/Projects/<owner>/<repo> is where every agent on this machine
      # expects a clone (the projects layout agent-kit installs).
      dir="''${AGENT_KIT_DIR:-${cfg.agentKitDir}}"
      if [ ! -d "$dir/.git" ]; then
        mkdir -p "$(dirname "$dir")"
        git clone https://github.com/JorisJonkers-dev/agent-kit "$dir"
      else
        # Never update a clone that is on a feature branch or has local
        # changes: a pull there leaves the machine on stale code.
        branch="$(git -C "$dir" rev-parse --abbrev-ref HEAD)"
        if [ "$branch" = "HEAD" ]; then
          echo "agent-kit-setup: $dir is in detached HEAD state, not on main. Run: git -C \"$dir\" switch main" >&2
          exit 1
        elif [ "$branch" != "main" ]; then
          echo "agent-kit-setup: $dir is on '$branch', not main. Run: git -C \"$dir\" switch main" >&2
          exit 1
        fi
        changes="$(git -C "$dir" status --porcelain)"
        if [ -n "$changes" ]; then
          echo "agent-kit-setup: $dir has uncommitted or untracked changes. Commit or stash them and run again." >&2
          exit 1
        fi
        git -C "$dir" pull --ff-only
      fi
      cd "$dir"
      exec ./installer/setup-workstation.sh "$@"
    '';
  };

  groupOption = name: default:
    lib.mkOption {
      type = lib.types.bool;
      inherit default;
      description = "Install the ${name} group of agent-kit's NixOS package list.";
    };
in {
  imports = [../unfree.nix];

  options.platformBlueprints.roles.devWorkstation = {
    enable = lib.mkEnableOption "dev workstation role: the toolchains, language servers and CLI tools agent-kit lists for NixOS";

    groups = {
      kubernetes.enable = groupOption "Kubernetes and GitOps" true;
      latex.enable = groupOption "LaTeX, pandoc and mdbook" true;
      polyglot.enable = groupOption "Ruby, .NET, Swift and C/C++" true;
      android.enable = groupOption "Android" false;
    };

    containerEngine = lib.mkOption {
      type = lib.types.enum ["rootless" "rootful"];
      default = "rootless";
      description = ''
        rootless runs Docker per user, with DOCKER_HOST pointing at the user's
        socket, so no group is root-equivalent; testcontainers works with it.
        rootful is the system daemon, for a repository that breaks without it.
      '';
    };

    agentKitDir = lib.mkOption {
      type = lib.types.str;
      default = "$HOME/Projects/JorisJonkers-dev/agent-kit";
      description = "Where agent-kit-setup keeps its agent-kit clone; AGENT_KIT_DIR overrides it at run time.";
    };

    packages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = lib.concatMap resolveGroup enabledGroups;
      defaultText = lib.literalMD "the enabled groups of agent-kit's NixOS package list";
      readOnly = true;
      description = "Packages the role installs from agent-kit's list.";
    };
  };

  # The package list comes from agent-kit's registry
  # (registry/generated/nixos/packages.nix), so tools are declared there, not
  # here. This module adds only what the role itself needs to work.
  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      environment.systemPackages =
        cfg.packages
        ++ [
          agentKitSetup
          # pnpm and yarn shims that follow each repository's packageManager
          # field, so pnpm 9, 11 and 12 repositories each get their own pin.
          pkgs.corepack_24
          # agent-kit's secret store checks for a key with gdbus.
          pkgs.glib
        ]
        ++ lib.optional (ownPackages ? opencode) ownPackages.opencode;

      # Prebuilt binaries agent-kit downloads (the Claude Code native build,
      # MCP servers fetched by npx, mise-installed toolchains, OpenCode) are
      # dynamically linked against a normal glibc layout; nix-ld provides the
      # loader they look for.
      programs.nix-ld.enable = true;

      # jdtls runs `java`, and Gradle repositories expect JAVA_HOME.
      programs.java = {
        enable = true;
        package = pkgs.jdk21;
      };

      # agent-kit keeps its secrets in the Secret Service.
      services.gnome.gnome-keyring.enable = lib.mkDefault true;

      # `npm install -g` cannot write into the Nix store. Point it at a
      # per-user prefix and put that and ~/.local/bin on PATH.
      environment.sessionVariables.NPM_CONFIG_PREFIX = "$HOME/.npm-global";
      environment.extraInit = lib.mkAfter ''
        export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$PATH"
      '';

      # vault is unfree (BSL); allowed only while the group that installs it
      # is on.
      platformBlueprints.unfree.packages = lib.optional cfg.groups.kubernetes.enable "vault";
    }
    (lib.mkIf (cfg.containerEngine == "rootless") {
      virtualisation.docker.rootless = {
        enable = true;
        setSocketVariable = true;
      };
    })
    (lib.mkIf (cfg.containerEngine == "rootful") {
      virtualisation.docker.enable = true;
    })
  ]);
}
