# Changelog

## [0.4.1](https://github.com/JorisJonkers-dev/nixos-modules/compare/v0.4.0...v0.4.1) (2026-10-19)


### Bug Fixes

* **k3s:** want requiredServices instead of requiring them, so restarting one never stops k3s ([#14](https://github.com/JorisJonkers-dev/nixos-modules/issues/14)) ([e5dac3d](https://github.com/JorisJonkers-dev/nixos-modules/commit/e5dac3d32a216b2cc4ae9632444f6bb945b8f8e4))

## [0.4.0](https://github.com/JorisJonkers-dev/nix-platform/compare/v0.3.0...v0.4.0) (2026-06-29)


### Features

* extract reusable nix platform modules ([#6](https://github.com/JorisJonkers-dev/nix-platform/issues/6)) ([12a5dfc](https://github.com/JorisJonkers-dev/nix-platform/commit/12a5dfcc7a671a610d4c782a101e8da88852a7a2))

## [0.3.0](https://github.com/JorisJonkers-dev/nix-platform/compare/v0.2.0...v0.3.0) (2026-06-29)


### Features

* add deploy-v2 nix platform roles ([#3](https://github.com/JorisJonkers-dev/nix-platform/issues/3)) ([767f1a4](https://github.com/JorisJonkers-dev/nix-platform/commit/767f1a4780061521d18e5e5de9339130a549aa43))

## [0.2.0](https://github.com/JorisJonkers-dev/nix-platform/compare/v0.1.0...v0.2.0) (2026-06-28)


### Features

* assemble reusable nix platform flake ([#1](https://github.com/JorisJonkers-dev/nix-platform/issues/1)) ([9bf9705](https://github.com/JorisJonkers-dev/nix-platform/commit/9bf97054ad3c39e344ee366e372a42501a9a12ff))
* **t1000:** add ntfs3g userspace tools to system PATH ([#198](https://github.com/JorisJonkers-dev/nix-platform/issues/198)) ([cd3b163](https://github.com/JorisJonkers-dev/nix-platform/commit/cd3b16379f7ed24fc53a8891a4184471368a5e9b))
* **t1000:** declare second M.2 as btrfs /srv/backup in disko ([#196](https://github.com/JorisJonkers-dev/nix-platform/issues/196)) ([2ee2569](https://github.com/JorisJonkers-dev/nix-platform/commit/2ee2569f5d1448eb09ddde34473548c7c496e7a6))


### Bug Fixes

* **dns:** cap nameservers at 3 to stay under glibc MAXNS ([#184](https://github.com/JorisJonkers-dev/nix-platform/issues/184)) ([4aa5d61](https://github.com/JorisJonkers-dev/nix-platform/commit/4aa5d61aded854242e8f467b647672da761f9faf))
* **dns:** Cloudflare upstream fleet-wide + ndots:2 on Jellyfin ([#178](https://github.com/JorisJonkers-dev/nix-platform/issues/178)) ([600c282](https://github.com/JorisJonkers-dev/nix-platform/commit/600c282c306b71e864d92576c02f35089e0be39e))
* **dns:** write /etc/resolv.conf statically, disable openresolv merge ([#188](https://github.com/JorisJonkers-dev/nix-platform/issues/188)) ([133e3dd](https://github.com/JorisJonkers-dev/nix-platform/commit/133e3dd20ec6333736d386f16463a4be6e2a6148))
* **downloads:** make /srv/media-incomplete writable by qBittorrent ([#681](https://github.com/JorisJonkers-dev/nix-platform/issues/681)) ([c680bd8](https://github.com/JorisJonkers-dev/nix-platform/commit/c680bd82cfee4f600b8bfa680f76f03557290b25))
* **t1000:** nofail + device-timeout on /srv/backup mounts ([#197](https://github.com/JorisJonkers-dev/nix-platform/issues/197)) ([e9623cf](https://github.com/JorisJonkers-dev/nix-platform/commit/e9623cf33038a87636d12ef6738af8a689fcee1f))
* **t1000:** pin disko disk.main to by-id path ([#199](https://github.com/JorisJonkers-dev/nix-platform/issues/199)) ([eb801e1](https://github.com/JorisJonkers-dev/nix-platform/commit/eb801e13fe4c351aae9f53a3482c58ba1850df0c))


### Reverts

* t1000 /srv/media — drop redundant device= mount options ([#233](https://github.com/JorisJonkers-dev/nix-platform/issues/233)) ([aeb59dc](https://github.com/JorisJonkers-dev/nix-platform/commit/aeb59dcb56363be4690d3ee9e6910e8e808c486d))

## 0.1.0

- Initial reusable NixOS module flake for JorisJonkers-dev platform hosts.
