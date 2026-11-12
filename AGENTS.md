# Agents

Guidance for any coding agent working in this repository.

The repository's agent contract is [CLAUDE.md](CLAUDE.md). The estate-wide conventions (labels, traps) are in the [estate contract](https://github.com/JorisJonkers-dev/workspace/blob/main/CLAUDE.md); read both before non-trivial changes.

This is a shared Nix artifact: reusable NixOS modules (`modules`), a helper library (`lib`) and packages (`pkgs`). It holds no host inventory, cluster state or secrets. Fixtures live in `tests`.

## Build and test

- `nix flake check --print-build-logs` is the local validation the README documents (`README.md`, "Local Validation").
