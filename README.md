# Devcontainer Images

Prebuilt multi-arch Docker images for Coder workspaces, published to GHCR. Each image layers a language toolchain on a shared base of system-level tooling. The Coder Terraform template lives in `./coder-template/`.

![CI](https://github.com/TomGrozev/devcontainers/actions/workflows/build.yml/badge.svg)

## Images

| Image | Language | Contents |
| --- | --- | --- |
| `devcontainer-base` | — | System tools, CLI utilities, user setup |
| `devcontainer-elixir` | Elixir | Base + Erlang/OTP + Elixir + mix/hex |
| `devcontainer-rust` | Rust | Base + Rust (rustup) + cargo |

All images run as user `dev` (UID/GID 1000), shell `/bin/zsh`, locale `en_AU.UTF-8`.

## Shared Base (`devcontainer-base`)

- Debian trixie-slim
- Node.js 22 + GitHub CLI
- Neovim (multi-arch, `/opt/nvim`)
- rtk, delta, ripgrep, bat, OpenCode, omp (system binaries on PATH)
- apt packages: build-essential, gcc, g++, git, jq, fzf, zsh, gpg, openssh-client, curl, ca-certificates, procps, sudo, unzip, zoxide, tmux, locales
- Rootless `su`/`sudo` passthrough wrappers
- User `dev` UID/GID 1000, `/etc/zsh/zshrc` skeleton

## Elixir (`devcontainer-elixir`)

- Erlang/OTP + Elixir via `COPY --from=hexpm/elixir`
- `inotify-tools` for Phoenix live-reload
- `MIX_HOME=/home/dev/.mix`, `HEX_HOME=/home/dev/.hex`
- First-time mix/hex bootstrap on workspace start

## Rust (`devcontainer-rust`)

- Rust via `rustup-init` (minimal profile + `rustfmt`, `clippy`, `rust-analyzer`, `rust-src`)
- `pkg-config` and `libssl-dev` for `openssl-sys` crates
- `RUSTUP_HOME` and `CARGO_HOME` split for PVC compatibility

## What's Deferred

- **opencode** — installed at first workspace start by the `coder-labs/opencode` module
- **zsh + oh-my-zsh + powerlevel10k + fzf** — applied via dotfiles
- **asdf** — managed by dotfiles
- **Language-specific bootstraps** — run once on first workspace start via `/usr/local/share/devcontainer/bootstrap.sh`

## Tags

Each image has a **train tag** (`vX.Y.Z`) — immutable, guarantees all three images share the same base layers from the same build run. **Toolchain tags** are moving and describe what's inside.

### `devcontainer-base`

| Tag | Immutable | Answers |
| --- |:---:| --- |
| `latest` | no | Newest base |
| `vX.Y.Z` | yes | Base from train X.Y.Z |
| `sha-<short>` | yes | Which commit built this |
| `debian-trixie` | no | Newest base on this distro |

### `devcontainer-elixir`

| Tag | Immutable | Answers |
| --- |:---:| --- |
| `latest` | no | Newest Elixir image |
| `vX.Y.Z` | yes | Same train as base + Rust |
| `sha-<short>` | yes | Which commit built this |
| `elixir-X.Y` | no | Latest patches on this Elixir minor |
| `elixir-X.Y.Z-otp-X.Y.Z` | no | This exact toolchain, freshest tooling |
| `vX.Y.Z-elixir-X.Y.Z-otp-X.Y.Z` | yes | Fully pinned + self-describing |

### `devcontainer-rust`

| Tag | Immutable | Answers |
| --- |:---:| --- |
| `latest` | no | Newest Rust image |
| `vX.Y.Z` | yes | Same train as base + Elixir |
| `sha-<short>` | yes | Which commit built this |
| `rust-X.Y` | no | Latest patches on this Rust minor |
| `rust-X.Y.Z` | no | This exact toolchain |
| `vX.Y.Z-rust-X.Y.Z` | yes | Fully pinned + self-describing |

## Usage

The Coder Terraform template in `./coder-template/` deploys the selected image as a rootless Kubernetes pod with a persistent home PVC, dotfiles, and opencode. See `coder-template/README.md` for setup instructions including the OpenCode user-secret one-liner.

To rebuild images manually: trigger **Actions > Build and Push > Run workflow**. The workflow builds `linux/amd64` + `linux/arm64` and pushes all three images to GHCR.

## Versions

<!-- versions:start -->
| Component | Version |
| --- | --- |
| Elixir | 1.20.3 |
| Erlang/OTP | 28.5.0.5 |
| Rust | 1.98.1 |
| Debian | trixie-20260803-slim |
| Neovim | v0.12.5 |
| Node.js (major) | 24 |
| rtk | v0.48.0 |
| delta | 0.19.2 |
| ripgrep | 15.2.0 |
| bat | 0.26.1 |
| OpenCode | 1.18.29 |
| omp | 18.1.13 |
<!-- versions:end -->

*Generated at release time by `scripts/gen-readme-versions.sh`.*

## Notes

- The `dev` user has UID/GID 1000.
- Images run rootless: pod securityContext drops all capabilities and forbids privilege escalation. The `su`/`sudo` wrappers passthrough commands as the current user.
- Persistent state lives under `/home/dev` (mounted on a PVC in Coder); rebuilds of the image do not affect workspace state.
- This project is Coder-only — it does not ship a `devcontainer.json` entrypoint.
