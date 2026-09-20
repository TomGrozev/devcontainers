# Coder Template: Multi-Language Workspace (Kubernetes)

A [Coder](https://coder.com) template that deploys a language-specific dev container on Kubernetes. The template takes a `language` parameter (choices: `elixir`, `rust`) and picks the right prebuilt image for it. The `image` parameter is an override that defaults to empty — leave it unset to auto-compute the image from `language`.

This template runs a prebuilt image directly (no build step), giving you:

- **Faster workspace startup** — no build step
- **Smaller surface area** — fewer moving parts to debug
- **Predictable behavior** — what you test locally is what runs in Coder

The image is a full dev environment for the chosen language. See the [image README](../README.md) for general details, or the **Languages** section below for what each image bundles.

## Prerequisites

- A running [Coder](https://coder.com) deployment (v2.x or later)
- A Kubernetes cluster reachable from the Coder host
- (Optional) A `~/.kube/config` if the Coder host runs outside the cluster

## Quick start

1. Create a new template in your Coder deployment, pointing at this directory.
2. Optionally override variables (namespace) and parameters (language, image, repo, cpu, memory, volume size, storage class, dotfiles URI).
3. Create a new workspace from the template.

## Variables

Variables are set at template build time (not at workspace creation). They configure the Terraform providers and the target infrastructure.

| Variable         | Type   | Default | Description                                                                                                                    |
| ---------------- | ------ | ------- | ------------------------------------------------------------------------------------------------------------------------------ |
| `use_kubeconfig` | bool   | `false` | Controls the `kubernetes` provider `config_path`. Set `true` if the Coder host runs outside the cluster and `~/.kube/config` is present. When `false` the provider uses in-cluster auth. |
| `namespace`      | string | `dev`   | Kubernetes namespace where the PVC and Deployment are created.                                                                 |

## Parameters

Parameters are configurable from the Coder UI at workspace creation or (for mutable ones) via workspace updates.

| Parameter            | Default                                        | Mutable | Description                                                                      |
| -------------------- | ---------------------------------------------- | ------- | -------------------------------------------------------------------------------- |
| `language`           | `"elixir"`                                      | yes     | Language stack to deploy. Choices: `elixir`, `rust`. Determines the default image. |
| `image`              | `""`                                            | yes     | Container image override. Leave empty to auto-compute from `language`.          |
| `repo`               | `""`                                           | yes     | Git repo URL to clone into `/home/dev/workspace` (leave empty for no auto-clone) |
| `cpu`                | `4`                                            | yes     | CPU limit (cores)                                                                |
| `memory`             | `8`                                            | yes     | Memory limit (GiB)                                                               |
| `home_volume_size`   | `20`                                           | no      | `/home/dev` volume size (GiB)                                                    |
| `storage_class_name` | `""`                                           | no      | Kubernetes StorageClass (empty = cluster default)                                |
| `dotfiles_uri`       | `https://github.com/TomGrozev/dots`            | yes     | Git repo URL containing dotfiles, applied by the startup script and the Refresh Dotfiles button |
| `git_name`           | `""`                                           | yes     | Git user name for commits. Leave empty to use workspace owner name or existing git config. |
| `git_email`          | `""`                                           | yes     | Git email for commits. Leave empty to use workspace owner email or existing git config. |

## What this template uses

| Resource                                  | Purpose                                                                                                                                                                                                                                            |
| ----------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `coder_agent.main`                        | Registers the Coder agent in the workspace. Works in `/home/dev/workspace`.                                                                                                                                                                        |
| `coder_agent.main.startup_script`         | Inlines first-time setup: creates `/home/dev/{workspace,.local/bin,.local/share,.config,.ssh}`, sets global git identity if not already configured, runs the language-specific `bootstrap.sh` if present, clones a repo if set, hard-syncs dotfiles to their upstream branch before applying via `coder dotfiles`, and removes the legacy `tau-mirror` omp extension from older PVCs. captain-miao config is dotfiles-owned. |
| `kubernetes_persistent_volume_claim_v1.home` | Persistent `/home/dev` across workspace restarts. Labelled with Coder workspace, user, and resource metadata.                                                                                                                                  |
| `kubernetes_deployment_v1.main`           | Runs the container rootless (UID/GID 1000, all capabilities dropped, seccomp `RuntimeDefault`), uses `Recreate` strategy, applies pod anti-affinity, and sets CPU/memory requests and limits from the `cpu`/`memory` parameters.                    |
| `coder_script.zellij_web`                 | On-start script that runs under `zsh` (so `~/.zshenv` is sourced and its environment — the proper omp environment — is inherited by the daemon), then mints a zellij web login token once (stored on the PVC) and daemonizes `zellij web` on loopback `:8082` for mobile browser access.                        |
| `coder_app.opencode`                      | Proxies the opencode server via subdomain (`http://localhost:4096`). Healthy only while a session started by the Start opencode button is running. Healthcheck at `/global/health`.                                                                 |
| `coder_script.ompweb`                     | On-start script that daemonizes the ompweb server via `npx -y @kahme247/ompweb` (npm cache on PVC) under `zsh` (inheriting `~/.zshenv` PATH). Runs once at boot.                                                                                              |
| `coder_app.ompweb`                        | Proxies the ompweb browser UI for omp via subdomain (`http://localhost:30177`). Healthy while the ompweb daemon is running. Healthcheck at `/api/home`.                                                                                                |
| `coder_app.restart_ompweb`               | Button: kills and relaunches the ompweb daemon (useful for recovering wedged processes or updating versions).                                                                                                                                     |
| `coder_app.start_opencode`                | Button: launches opencode (TUI + server in one process) in the miao pool, binding its server to loopback `:4096` (idempotent).                                                                                                                    |
| `coder_app.zellij_web`                    | Proxies the zellij web terminal via subdomain (`http://localhost:8082`); lands on zellij's session picker. First visit asks for a login token.                                                                                                     |
| `coder_app.zellij_token`                  | Button: prints the zellij web login token minted at boot (zellij never re-displays it).                                                                                                                                            |
| `coder_app.refresh_dotfiles`              | A workspace-app button that re-runs `coder dotfiles` against the current `dotfiles_uri` value to pull the latest dotfiles and re-apply.                                                                                                            |

## Agent environment variables

The following environment variables are set in the workspace container:

| Variable         | Value                          | Purpose                                                              |
| ---------------- | ------------------------------ | -------------------------------------------------------------------- |
| `CODER_AGENT_TOKEN` | `coder_agent.main.token`     | Coder agent authentication (required).                               |
| `DEVCONTAINER`   | `"true"`                       | Container detection used by dotfiles (e.g. permissive opencode permission tier). |
| `CODER_CONFIG_DIR` | `/home/dev/.config/coderv2`  | Coder CLI global config dir; `coder dotfiles` keeps its checkout at `<dir>/dotfiles`. |

The agent's working directory is `/home/dev/workspace`.

## Sessions and mobile access

Both coding agents run server-side so a session started from the laptop keeps running when the laptop closes, and is reachable from a phone on the LAN through the Coder dashboard.

+ **omp** — The **ompweb** browser UI is started at boot as a standalone daemon on `:30177` (not a pty session, so it does not live in the miao pool). It spawns omp agents directly as child processes. Open the **ompweb** app to browse sessions and drive new ones. Use the **Restart ompweb** button if the daemon hangs. **Start opencode** and **OpenCode** are the opencode equivalents.
- **opencode** — the **Start opencode** button runs `opencode` with `--hostname 127.0.0.1 --port 4096` inside the pool, so the **OpenCode** web app and a laptop `opencode attach http://localhost:4096` both talk to the same session store and can hand off mid-task (including permission approvals).
- **Zellij (terminal)** — the **Zellij** app is a full mobile terminal served by zellij web on `:8082`. On first visit, copy the token from the **Zellij token** button (one paste per device, remembered for ~4 weeks).

Everything serving over HTTP binds loopback only and is reached through Coder's authenticated subdomain proxy — nothing is exposed directly on the network.

## captain-miao config

The shared config ships in dotfiles at `~/.config/captain-miao/config.toml` (symlinked by `install.sh`); the template no longer writes it:

```toml
[launcher]
default_agent = "omp"

[terminal]
sessions_layout = "per-tab"

[remote]
on_window_close = "detach"
```

- `default_agent = "omp"` sets the backend new sessions (`o`/`O`) open with.
- `sessions_layout = "per-tab"` gives each session its own tab.
- `on_window_close = "detach"` makes closing a dashboard window detach rather than kill the session.

**Pooled mode is per-host, not shared.** `pooled` is deliberately absent from the shared file. Dev servers want pooling (sessions survive disconnects and are steal-able from a remote dashboard); laptops stay direct-local. The dotfiles' `install.sh` enables it only inside the workspace, writing:

```json
{"prefs": {"pooled": true}}
```

to `~/.local/state/captain-miao/dashboard-overrides.json` when `DEVCONTAINER=true`. That file is read only by the dashboard and overlays the config without touching the symlinked `config.toml`. A parse error anywhere in `config.toml` reverts *every* section to defaults — keep it valid.

The `miao` and `miao-server` binaries ship in the image (pinned in `docker-bake.hcl`).

## How it works

1. Coder applies this Terraform against your Kubernetes cluster.
2. A `PersistentVolumeClaim` is created in the configured namespace.
3. A `Deployment` is created that runs the prebuilt image as a rootless container (UID 1000, all capabilities dropped, seccomp `RuntimeDefault`).
4. The main container runs `coder_agent.main.init_script`, which bootstraps the agent and connects to the Coder server.
5. The agent's `startup_script` runs first-time init:
   - Creates `/home/dev/{workspace,.local/bin,.local/share,.config,.ssh}`.
   - Sets global git identity only if not already configured.
   - Git safety for `/home/dev/workspace` comes from the deployment's `GIT_CONFIG_COUNT`/`GIT_CONFIG_KEY_0`/`GIT_CONFIG_VALUE_0` env vars, not from a write to `~/.gitconfig`.
   - Runs the language-specific `bootstrap.sh` from `/usr/local/share/devcontainer/` if present.
   - Clones the `repo` parameter into `/home/dev/workspace` if set and not already a git repo.
   - Applies dotfiles via `coder dotfiles <dotfiles_uri> -y` (hard-reset to upstream branch first), re-applied on every start.
6. The `coder_script.zellij_web` script (also on start) mints the zellij web token once and daemonizes the zellij web server — wrapped in `zsh -c` so `~/.zshenv` is sourced and the daemon (and every session it spawns) runs with the user's proper omp environment.
7. The `coder_app` resources register the dashboard buttons and web-app tiles described above.

## Customization

### Choosing a language

Set the `language` parameter to either `elixir` or `rust`. The template picks the right prebuilt image automatically — leave `image` empty to use the default.

```hcl
language = "rust"  # or "elixir"
```

### Using a different image

Override the `image` parameter in the Coder UI. The image must:

- Be runnable as a non-root user (UID 1000, GID 1000)
- Have a writable home directory at `/home/dev`
- Have `curl` and `sh` for the coder agent installer
- Include the toolchain expected for the chosen `language` (e.g. `mix`/`hex` for Elixir, `cargo`/`rustup` for Rust)
- Include `zellij`, `miao`, `miao-server`, `omp`, and `opencode` for the session/mobile workflow above

### Adding a repo to clone on startup

Set the `repo` parameter in the Coder UI (e.g. `git@github.com:you/repo.git`). The startup script clones it into `/home/dev/workspace`.

### Changing your dotfiles

The `dotfiles_uri` parameter controls which dotfiles repo is applied (mutable, so you can swap it per-workspace). The startup script applies dotfiles on every start; to refresh dotfiles without restarting, use the **Refresh Dotfiles** button in the workspace dashboard.

The checkout at `/home/dev/.config/coderv2/dotfiles` is a deploy staging area, not a place to edit — it is the coder CLI's own config dir plus its `--repo-dir` (default `dotfiles`), i.e. `$CODER_CONFIG_DIR/dotfiles`, not a path this template chooses. `install.sh` symlinks `~/.gitconfig`, `~/.zshrc` etc. from it into `$HOME`, so editing those files in a running workspace modifies the checkout. On every start (and via **Refresh Dotfiles**) it is hard-reset to its upstream branch and untracked files are cleaned before `coder dotfiles` re-applies it, so it can never get stuck dirty and dotfiles always reflect the repo — local changes to it are discarded, never applied, so make dotfile changes in the dotfiles repo (github.com/TomGrozev/dots), not in a workspace.

### Using a private image registry

Add an `image_pull_secrets` block to the container spec and create the corresponding Kubernetes secret in the workspace namespace:

```hcl
image_pull_secrets {
  name = "regcred"
}
```

## Troubleshooting

### The agent keeps restarting

Check the workspace logs. The most common cause is the agent failing to download or install. Ensure the container has internet access.

### Permission errors on `/home/dev`

The PVC might be owned by a different UID from a previous session. The deployment sets `fs_group=1000` with `fs_group_change_policy=Always`, which should reclaim ownership. If it doesn't, run a one-off pod with `chown`, or delete the PVC and recreate the workspace.

### Elixir tooling not found

For Elixir workspaces, the startup script runs `mix local.hex --force` on first start. If mix is not in the image, the bootstrap will fail. Ensure your `image` includes Elixir/Erlang, or that the auto-computed image for your `language` is reachable.

### Start ompweb / Start opencode reports it's already running

+ The buttons are idempotent and exit early when their health endpoint is reachable. If that's wrong (the process is dead but the port is still held), stop it and start fresh. For **ompweb**, use the **Restart ompweb** button or kill the daemon manually (e.g. `pkill -f '@kahme247/ompweb'`); its agents are child processes and die with the daemon. For **opencode**, stop the pooled session from the miao dashboard (`x`), or run `miao-server daemon stop` to tear the pool down and start fresh.

### Dotfiles did not update

The apply log lives at `/home/dev/.dotfiles.log`. The dotfiles checkout is at `/home/dev/.config/coderv2/dotfiles`. If the log shows a clone/pull error, check that the workspace has network access and that `dotfiles_uri` is reachable.

## Languages

The prebuilt image for each `language` value bundles the following toolchain:

- **Elixir**: Erlang/OTP, Elixir, mix, hex, inotify-tools
- **Rust**: rustup, cargo, rustfmt, clippy, rust-analyzer, rust-src, pkg-config, libssl-dev

Both images also include Node.js, Neovim, zsh, fzf, delta, rtk, zellij, captain-miao (`miao` + `miao-server`), omp, and the opencode CLI.
