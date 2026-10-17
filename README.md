# Devcontainer Images

Prebuilt multi-arch Docker images for Coder workspaces, published to GHCR. Each image layers a language toolchain on a shared base of system-level tooling. The Coder Terraform template lives in `./coder-template/`.

![CI](https://github.com/TomGrozev/devcontainers/actions/workflows/build.yml/badge.svg)

## Images

| Image | Language | Contents |
| --- | --- | --- |
| `devcontainer-base` | — | System tools, CLI utilities, user setup |
| `devcontainer-elixir` | Elixir | Base + Erlang/OTP + Elixir + mix/hex |
| `devcontainer-rust` | Rust | Base + Rust (rustup) + cargo |
| `devcontainer-agent-elixir` | omp | Elixir (layers on `devcontainer-elixir`) + omp headless config, Kelos entrypoint; dotfiles (skills, plugins) applied at pod start |
| `devcontainer-agent-rust` | omp | Rust (layers on `devcontainer-rust`) + omp headless config, Kelos entrypoint; dotfiles (skills, plugins) applied at pod start |

All images except the agent images run as user `dev` (UID/GID 1000), shell `/bin/zsh`, locale `en_AU.UTF-8`. The agent images (`devcontainer-agent-elixir`, `devcontainer-agent-rust`) run as user `agent` (UID/GID 61100).

## Shared Base (`devcontainer-base`)

- Debian trixie-slim
- `node` (Bun via a thin wrapper) + npm/npx standalone + GitHub CLI
- Neovim (multi-arch, `/opt/nvim`)
- rtk, delta, ripgrep, bat, omp, git-graph, d2, yazi (system binaries on PATH)
- apt packages: build-essential, gcc, g++, git, file, jq, fzf, zsh, gpg, openssh-client, curl, ca-certificates, procps, sudo, unzip, zoxide, tmux, locales
- Chromium runtime libraries so `omp`'s browser tool can launch its bundled browser (NSS/NSPR, ATK, AT-SPI, CUPS, ALSA, Mesa/GBM, X11, Pango, Cairo)
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

## Agent (`devcontainer-agent-elixir`, `devcontainer-agent-rust`)

An unattended omp agent, built to run as a [Kelos](https://github.com/kelos-dev/kelos) task pod rather than as an interactive workspace. Kelos clones the repo, then runs the container command; nothing here is driven by a human at a terminal.

The agent layer is language-independent: one Dockerfile, one headless config overlay, one Kelos entrypoint, shared by the family. The only thing that differs per image is the language layer underneath — `devcontainer-agent-elixir` layers on `devcontainer-elixir`, `devcontainer-agent-rust` on `devcontainer-rust`. Adding a language is a new bake target that inherits the existing agent target plus one `contexts.base` line pointing at the language image. A repo whose language has no matching agent image can still use one and install its toolchain through the Kelos `KELOS_SETUP_COMMAND`.

- Layers on the language image (omp itself comes from the shared base)
- Runs as user `agent`, **UID/GID 61100** — Kelos's `AgentUID`. Kelos sets `RunAsUser: 61100` on the `git-clone` init container and `FSGroup: 61100` on the pod, but not on the agent container, so the image's own `USER 61100` is what makes the agent process match the workspace's owner.
- Ships `/kelos_entrypoint.sh` (mode 0755) — Kelos sets the container command to that exact path with the task prompt as `$1`, overriding any `ENTRYPOINT` in the image. It reads `DOTFILES_URI`, `DOTFILES_REF`, `KELOS_SETUP_COMMAND`, `OMP_SKILL`, and `OMP_MAX_TIME`; see the script header for the contract each one carries. Credentials (provider API keys, git identity) are deployment concerns: inject them as env vars or mounted files in the pod spec, the same way a Coder workspace gets them, so the image stays setup-agnostic. Before the agent starts it indexes `/workspace/repo` with `codebase-memory-mcp` so the graph is ready on the first turn.
- Headless omp config overlay at `/etc/omp/agent-image/agent.yml`, wired in through `PI_CONFIG_FILES` (omp's platform path-list of overlays, loaded before any `--config`)
- Dotfiles-agnostic: no dotfiles repo is baked in. The entrypoint clones `DOTFILES_URI` (required) at `DOTFILES_REF` (optional; the remote's default branch when unset) into `$HOME/dotfiles` at pod start and runs its own `install.sh` with `AGENT_POD=true` — the agent-pod mode that skips the shell and tool installs. That installer, not the image, provides the `.omp` instructions, rules, config, subagents, extensions, the `implement`/`walkthrough`/`land` skills, and `pairing-workflow.html`; the `cc-safety-net` policy; the omp plugins (`cc-safety-net` and the NeuralWatt provider); and the `tdd`, `code-review`, `conventional-commit`, `frontend-design` and `apple-design` skills under `~/.agents/skills`. The entrypoint exits non-zero naming `DOTFILES_URI` when it is unset, and names the installer as the cause when it fails, so a task that forgets it — or a layout change — fails loudly instead of running as a bare agent.
- `/home/agent/.local/bin` is pre-created, agent-owned, and first on `PATH`, so a workspace `setupCommand` can install tools the agent then resolves by name
- `OMP_MCP_REQUIRE_READY=1`, so print mode exits 1 if a configured MCP server is still pending or has failed, rather than running the turn without it

## What's Deferred

- **zsh + oh-my-zsh + powerlevel10k + fzf** — applied via dotfiles
- **asdf** — managed by dotfiles
- **Language-specific bootstraps** — run once on first workspace start via `/usr/local/share/devcontainer/bootstrap.sh`

## Tags

Each image has a **train tag** (`vX.Y.Z`) — immutable, guarantees all five images share the same base layers from the same build run. **Toolchain tags** are moving and describe what's inside.

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

### `devcontainer-agent-elixir`

| Tag | Immutable | Answers |
| --- |:---:| --- |
| `latest` | no | Newest agent image |
| `vX.Y.Z` | yes | Same train as base + Elixir |
| `sha-<short>` | yes | Which commit built this |
| `omp-X.Y` | no | Latest patches on this omp minor |
| `omp-X.Y.Z` | no | This exact omp version |
| `vX.Y.Z-omp-X.Y.Z` | yes | Fully pinned + self-describing |

### `devcontainer-agent-rust`

| Tag | Immutable | Answers |
| --- |:---:| --- |
| `latest` | no | Newest agent image |
| `vX.Y.Z` | yes | Same train as base + Rust |
| `sha-<short>` | yes | Which commit built this |
| `omp-X.Y` | no | Latest patches on this omp minor |
| `omp-X.Y.Z` | no | This exact omp version |
| `vX.Y.Z-omp-X.Y.Z` | yes | Fully pinned + self-describing |

## Usage

The Coder Terraform template in `./coder-template/` deploys the selected image as a rootless Kubernetes pod with a persistent home PVC and dotfiles. See `coder-template/README.md` for setup instructions.

To rebuild images manually: trigger **Actions > Build and Push > Run workflow**. The workflow builds `linux/amd64` + `linux/arm64` and pushes all five images to GHCR.

## Versions

<!-- versions:start -->
| Component | Version |
| --- | --- |
| Elixir | 1.20.3 |
| Erlang/OTP | 28.5.0.5 |
| Rust | 1.97.1 |
| Debian | trixie-20260803-slim |
| Neovim | v0.12.4 |
| npm | 11.19.0 |
| rtk | v0.45.0 |
| delta | 0.19.2 |
| ripgrep | 15.2.0 |
| bat | 0.26.1 |
| omp | 17.3.7 |
| git-graph | 0.8.0-3 |
| d2 | 0.9.0 |
| yazi | 26.9.1 |
<!-- versions:end -->

*Generated at release time by `scripts/gen-readme-versions.sh`.*

## Notes

- The `dev` user has UID/GID 1000.
- Images run rootless: pod securityContext drops all capabilities and forbids privilege escalation. The `su`/`sudo` wrappers passthrough commands as the current user.
- Persistent state lives under `/home/dev` (mounted on a PVC in Coder); rebuilds of the image do not affect workspace state.
- This project is Coder-only — it does not ship a `devcontainer.json` entrypoint.
