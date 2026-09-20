terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "~> 2.0"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
  }
}

provider "coder" {}
provider "kubernetes" {
  config_path = var.use_kubeconfig ? "~/.kube/config" : null
}

data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

variable "use_kubeconfig" {
  type        = bool
  description = "Use ~/.kube/config (set true if Coder host runs outside the cluster)."
  default     = false
}

variable "namespace" {
  type        = string
  default     = "dev"
  description = "Kubernetes namespace for workspace resources."
}

# ????????? Parameters ??????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????

data "coder_parameter" "language" {
  name         = "language"
  display_name = "Language"
  type         = "string"
  default      = "elixir"
  description  = "Language toolchain for the workspace image."
  mutable      = true
  order        = 1
  option {
    name  = "Elixir"
    value = "elixir"
  }
  option {
    name  = "Rust"
    value = "rust"
  }
}

data "coder_parameter" "image" {
  name         = "image"
  display_name = "Container Image"
  type         = "string"
  default      = ""
  description  = "Override the container image (defaults to the selected language)."
  mutable      = true
  order        = 2
}

data "coder_parameter" "repo" {
  name         = "repo"
  display_name = "Repository"
  type         = "string"
  default      = ""
  description  = "Git repo URL to clone (e.g. git@github.com:you/repo.git). Leave empty for no auto-clone."
  mutable      = true
  order        = 3
}

data "coder_parameter" "cpu" {
  name         = "cpu"
  display_name = "CPU"
  type         = "number"
  default      = "4"
  description  = "CPU limit (cores)."
  mutable      = true
  order        = 4
}

data "coder_parameter" "memory" {
  name         = "memory"
  display_name = "Memory"
  type         = "number"
  default      = "8"
  description  = "Memory limit (GiB)."
  mutable      = true
  order        = 5
}

data "coder_parameter" "home_volume_size" {
  name         = "home_volume_size"
  display_name = "Home Volume Size"
  type         = "number"
  default      = "20"
  description  = "Size of the /home/dev persistent volume (GiB)."
  mutable      = false
  order        = 6
}

data "coder_parameter" "storage_class_name" {
  name         = "storage_class_name"
  display_name = "Storage Class"
  type         = "string"
  default      = ""
  description  = "Kubernetes StorageClass (empty = cluster default)."
  mutable      = false
  order        = 7
}

data "coder_parameter" "dotfiles_uri" {
  name         = "dotfiles_uri"
  display_name = "Dotfiles Repository URI"
  type         = "string"
  default      = "https://github.com/TomGrozev/dots"
  description  = "Git repository URL containing your dotfiles (applied via `coder dotfiles`)."
  mutable      = true
  order        = 8
}

data "coder_parameter" "git_name" {
  name         = "git_name"
  display_name = "Git Name"
  type         = "string"
  default      = ""
  description  = "Git user name for commits. Leave empty to use workspace owner name or existing git config."
  mutable      = true
  order        = 9
}

data "coder_parameter" "git_email" {
  name         = "git_email"
  display_name = "Git Email"
  type         = "string"
  default      = ""
  description  = "Git email for commits. Leave empty to use workspace owner email or existing git config."
  mutable      = true
  order        = 10
}

# ????????? Locals ??????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????

locals {
  workspace_name = "coder-${lower(data.coder_workspace.me.id)}"
  # Git identity: prefer explicit parameters, then workspace owner data, then fallbacks
  git_name  = coalesce(data.coder_parameter.git_name.value, data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name, "TomGrozev")
  git_email = coalesce(data.coder_parameter.git_email.value, data.coder_workspace_owner.me.email, "dev@coder.com")
  image     = data.coder_parameter.image.value != "" ? data.coder_parameter.image.value : "ghcr.io/tomgrozev/devcontainer-${data.coder_parameter.language.value}:latest"

  # Where `coder dotfiles` actually keeps its checkout: the CLI joins its global
  # config dir with the `--repo-dir` value (cli/dotfiles.go:
  # filepath.Join(cfgDir, dotfilesRepoDir); --repo-dir defaults to "dotfiles",
  # env CODER_DOTFILES_REPO_DIR). On Linux that config dir defaults to
  # ~/.config/coderv2, so the checkout lands at the path below — NOT the
  # ~/.coder/dotfiles this template used to assume, which nothing ever created:
  # the `-d "$DOTFILES_DIR/.git"` guard below then skipped silently and the sync
  # was a no-op. CODER_CONFIG_DIR is pinned to the same local on the container
  # (see the env block) so the CLI's choice and this sync cannot drift apart.
  dotfiles_config_dir = "/home/dev/.config/coderv2"
  dotfiles_checkout   = "${local.dotfiles_config_dir}/dotfiles"

  # Hard-sync the dotfiles checkout to its upstream branch, then let
  # `coder dotfiles` re-apply it. The dotfiles repo's install.sh symlinks
  # ~/.gitconfig and friends into this checkout (and ~/.omp/agent/extensions
  # too), so ANY write to those files — a `git config --global` call, an edit
  # made from a workspace, a plugin install, an omp lock file — leaves the
  # checkout dirty, and the `git pull --ff-only` inside `coder dotfiles` then
  # refuses to run and silently re-applies the stale checkout instead, so the
  # dotfiles stop updating. This checkout is therefore kept as a mirror of the
  # remote: local changes are discarded, never applied. Shared by the startup
  # script and the Refresh Dotfiles button so the two cannot drift.
  dotfiles_sync = <<-EOT
    DOTFILES_DIR="${local.dotfiles_checkout}"
    if [ -d "$DOTFILES_DIR/.git" ]; then
      DOTFILES_BRANCH=$(git -C "$DOTFILES_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo master)
      DOTFILES_UPSTREAM="origin/$DOTFILES_BRANCH"
      git -C "$DOTFILES_DIR" fetch --prune origin || true
      git -C "$DOTFILES_DIR" reset --hard "$DOTFILES_UPSTREAM" || true
      git -C "$DOTFILES_DIR" clean -fd || true
    fi
  EOT
}

# ????????? Agent ?????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????

resource "coder_agent" "main" {
  arch = data.coder_provisioner.me.arch
  os   = "linux"

  startup_script = <<-EOT
    #!/bin/sh
    set -e

    # Ensure common dirs exist on the freshly-mounted PVC
    mkdir -p /home/dev/workspace /home/dev/.local/bin /home/dev/.local/share /home/dev/.config /home/dev/.ssh

    # Workspace safety for git (avoids dubious ownership errors) is supplied by
    # the GIT_CONFIG_* env vars on the deployment, NOT by a `git config
    # --global` write here: ~/.gitconfig is a symlink into the dotfiles
    # checkout, so writing it would dirty that checkout and block the dotfiles
    # sync below.

    # Set git identity only if not already configured
    if [ -z "$(git config --global user.name)" ]; then
      git config --global user.name "${local.git_name}"
    fi
    if [ -z "$(git config --global user.email)" ]; then
      git config --global user.email "${local.git_email}"
    fi

    # Run language-specific bootstrap if present
    if [ -x /usr/local/share/devcontainer/bootstrap.sh ]; then
      /usr/local/share/devcontainer/bootstrap.sh
    fi

    # Clone the repo parameter if set and not already present
    REPO="${data.coder_parameter.repo.value}"
    if [ -n "$REPO" ]; then
      if [ ! -e "/home/dev/workspace/.git" ]; then
        GIT_SSH_COMMAND="$GIT_SSH_COMMAND -o StrictHostKeyChecking=accept-new" \
          git clone "$REPO" /home/dev/workspace || true
      fi
    fi

    # Apply dotfiles synchronously. Inlined here (rather than via the
    # coder/dotfiles module) so anything dotfiles write to ~/.zshenv is
    # guaranteed to be in place before `opencode serve` starts below.
    # Always re-applies dotfiles on every workspace start.
    ${local.dotfiles_sync}
    GIT_SSH_COMMAND="$GIT_SSH_COMMAND -o StrictHostKeyChecking=accept-new" \
      coder dotfiles "${data.coder_parameter.dotfiles_uri.value}" -y 2>&1 | tee /home/dev/.dotfiles.log || true

    # The ompweb browser UI (kahme247/ompweb) is NOT installed here: it is a
    # standalone Node server (not an omp extension), run via npx by the Start
    # ompweb button as a plain daemon (npm cache lives on the PVC, so it
    # downloads once and stays warm). Remove the legacy
    # tau-mirror extension from older PVCs so it does not auto-load (non-fatal,
    # stdin-closed so any prompt fails fast instead of hanging startup).
    omp plugin uninstall --force tau-mirror </dev/null 2>/tmp/tau-uninstall.log || true

    # captain-miao config comes from the dotfiles: the shared config.toml, plus
    # (in this dev container) pooled mode enabled via install.sh writing
    # ~/.local/state/captain-miao/dashboard-overrides.json.
  EOT
}

# ????????? Persistent Volume Claim ???????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????

resource "kubernetes_persistent_volume_claim_v1" "home" {
  metadata {
    name      = "${local.workspace_name}-home"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/name"     = "${local.workspace_name}-home"
      "app.kubernetes.io/instance" = "${local.workspace_name}-home"
      "app.kubernetes.io/part-of"  = "coder"
      "com.coder.resource"         = "true"
      "com.coder.workspace.id"     = data.coder_workspace.me.id
      "com.coder.workspace.name"   = data.coder_workspace.me.name
      "com.coder.user.id"          = data.coder_workspace_owner.me.id
      "com.coder.user.username"    = data.coder_workspace_owner.me.name
    }
    annotations = {
      "com.coder.user.email" = data.coder_workspace_owner.me.email
    }
  }
  wait_until_bound = false
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "${data.coder_parameter.home_volume_size.value}Gi"
      }
    }
    storage_class_name = data.coder_parameter.storage_class_name.value != "" ? data.coder_parameter.storage_class_name.value : null
  }
}

# ????????? Deployment ??????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????

resource "kubernetes_deployment_v1" "main" {
  count = data.coder_workspace.me.start_count

  depends_on = [
    kubernetes_persistent_volume_claim_v1.home
  ]

  wait_for_rollout = false

  metadata {
    name      = local.workspace_name
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/name"     = "coder-workspace"
      "app.kubernetes.io/instance" = local.workspace_name
      "app.kubernetes.io/part-of"  = "coder"
      "com.coder.resource"         = "true"
      "com.coder.workspace.id"     = data.coder_workspace.me.id
      "com.coder.workspace.name"   = data.coder_workspace.me.name
      "com.coder.user.id"          = data.coder_workspace_owner.me.id
      "com.coder.user.username"    = data.coder_workspace_owner.me.name
    }
    annotations = {
      "com.coder.user.email" = data.coder_workspace_owner.me.email
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        "app.kubernetes.io/name" = "coder-workspace"
      }
    }

    strategy {
      type = "Recreate"
    }

    template {
      metadata {
        labels = {
          "app.kubernetes.io/name"   = "coder-workspace"
          "com.coder.resource"       = "true"
          "com.coder.workspace.pod"  = "true"
          "com.coder.workspace.name" = data.coder_workspace.me.name
        }
      }

      spec {
        # Pod-level security context (rootless)
        security_context {
          run_as_user            = 1000
          run_as_group           = 1000
          run_as_non_root        = true
          fs_group               = 1000
          fs_group_change_policy = "Always"
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        # Main workspace container
        # The init_script (from coder_agent.main) bootstraps the agent:
        # it downloads the coder CLI and runs "coder agent" which connects
        # to the Coder server. Source: Terraform provider agent docs example.
        container {
          name              = "dev"
          image             = local.image
          image_pull_policy = "Always"

          command = ["sh", "-c", coder_agent.main.init_script]

          security_context {
            run_as_user                = 1000
            run_as_group               = 1000
            run_as_non_root            = true
            allow_privilege_escalation = false
            capabilities {
              drop = ["ALL"]
            }
          }

          env {
            name  = "CODER_AGENT_TOKEN"
            value = coder_agent.main.token
          }

          env {
            name  = "DEVCONTAINER"
            value = "true"
          }

          env {
            name  = "ZELLIJ_AUTOATTACH"
            value = "0"
          }

          # Pin the coder CLI's global config dir. `coder dotfiles` clones and
          # updates "<config dir>/dotfiles", so this is what keeps the checkout
          # path in `local.dotfiles_checkout` — used by the sync that runs before
          # `coder dotfiles` — exact rather than a guess about the CLI default.
          env {
            name  = "CODER_CONFIG_DIR"
            value = local.dotfiles_config_dir
          }

          # safe.directory via git's env-config mechanism, which git treats as
          # "command line" scope — the highest-precedence protected config, so
          # it covers the ownership check without persisting anything to disk.
          # (The `git config --global safe.directory` in images/base runs as
          # root and lands in /root/.gitconfig, so it never reached the dev
          # user; writing it at startup instead would dirty the symlinked
          # ~/.gitconfig inside the dotfiles checkout.)
          env {
            name  = "GIT_CONFIG_COUNT"
            value = "1"
          }
          env {
            name  = "GIT_CONFIG_KEY_0"
            value = "safe.directory"
          }
          env {
            name  = "GIT_CONFIG_VALUE_0"
            value = "*"
          }

          resources {
            requests = {
              cpu    = "1"
              memory = "2Gi"
            }
            limits = {
              cpu    = data.coder_parameter.cpu.value
              memory = "${data.coder_parameter.memory.value}Gi"
            }
          }

          volume_mount {
            name       = "home"
            mount_path = "/home/dev"
            sub_path   = ""
          }
        }

        volume {
          name = "home"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.home.metadata[0].name
            read_only  = false
          }
        }

        affinity {
          pod_anti_affinity {
            preferred_during_scheduling_ignored_during_execution {
              weight = 1
              pod_affinity_term {
                topology_key = "kubernetes.io/hostname"
                label_selector {
                  match_expressions {
                    key      = "app.kubernetes.io/name"
                    operator = "In"
                    values   = ["coder-workspace"]
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}

# zellij web server + login token, started once at boot. The web server serves
# the mobile terminal (proxied via coder_app.zellij_web); login tokens are
# minted once and stashed on the PVC (zellij displays them only at creation),
# surfaced by coder_app.zellij_token. The script runs under zsh (via zsh -c)
# so the user's ~/.zshenv is sourced — zsh reads it for every invocation,
# not just interactive shells — and the daemonized web server (and every
# session it spawns) inherits the proper omp environment.
resource "coder_script" "zellij_web" {
  agent_id     = coder_agent.main.id
  display_name = "zellij web"
  icon         = "/icon/terminal.svg"
  run_on_start = true

  script = <<-EOT
    set -e

    # Run under zsh so ~/.zshenv is sourced (zsh reads it for every
    # invocation, including -c). The web server daemon — and every session
    # it spawns — inherits the user's proper omp environment instead of
    # the coder agent's bare one.
    zsh -c '
      set -e
      TOKEN_DIR=/home/dev/.local/share/captain-miao
      mkdir -p "$TOKEN_DIR"

      # Mint the login token once (zellij only shows a token when it is created).
      if [ ! -s "$TOKEN_DIR/zellij-web.token" ]; then
        zellij web --create-token > "$TOKEN_DIR/zellij-web.token" 2>/dev/null || true
        chmod 600 "$TOKEN_DIR/zellij-web.token"
      fi

      # Daemonize the web server if not already answering.
      if ! curl -sf http://localhost:8082 >/dev/null 2>&1; then
        zellij web --ip 127.0.0.1 --port 8082 --daemonize
      fi
    '
  EOT
}

# ompweb: browser UI for the omp coding agent (kahme247/ompweb via npx; npm
# cache lives on the PVC so it downloads once and stays warm). Started once at
# boot as a standalone Node daemon on loopback :30177 (a plain HTTP server, not
# a pty session, so it does not belong in the miao pool), proxied via
# coder_app.ompweb. Runs under a zsh login shell so ~/.zshenv supplies PATH and
# the devcontainer yolo overlay (PI_CONFIG_FILES), which ompweb's omp children
# inherit. ompweb spawns omp directly (plain `omp` on PATH) — its chat sessions
# are ompweb's own children, not captain-miao launches. The :30177 health guard
# keeps it idempotent (one ompweb at a time).
resource "coder_script" "ompweb" {
  agent_id     = coder_agent.main.id
  display_name = "ompweb"
  icon         = "/icon/code.svg"
  run_on_start = true

  script = <<-EOT
    set -e
    if curl -sf http://localhost:30177/api/home >/dev/null 2>&1; then
      echo "ompweb is already running"
      exit 0
    fi
    # setsid detaches the daemon from this script's session so it survives the
    # script returning; nohup guards SIGHUP. OMP_WEB_NO_OPEN keeps ompweb from
    # trying to open a browser.
    setsid nohup zsh -lc 'cd /home/dev/workspace && exec env OMP_WEB_NO_OPEN=1 npx -y @kahme247/ompweb --port 30177' >/tmp/ompweb.log 2>&1 </dev/null &
  EOT
}

resource "coder_app" "opencode" {
  agent_id     = coder_agent.main.id
  slug         = "opencode"
  display_name = "OpenCode"
  url          = "http://localhost:4096"
  subdomain    = true
  share        = "owner"
  open_in      = "tab"

  healthcheck {
    url       = "http://localhost:4096/global/health"
    interval  = 5
    threshold = 6
  }
}

# ompweb: browser UI for the omp coding agent. A standalone Node server running
# on loopback :30177 (started at boot by coder_script.ompweb as a plain daemon,
# not a miao pooled session), proxied via subdomain. Healthy only while that
# daemon is running.
resource "coder_app" "ompweb" {
  agent_id     = coder_agent.main.id
  slug         = "ompweb"
  display_name = "ompweb"
  icon         = "/icon/code.svg"
  url          = "http://localhost:30177"
  subdomain    = true
  share        = "owner"
  open_in      = "tab"

  healthcheck {
    url       = "http://localhost:30177/api/home"
    interval  = 5
    threshold = 6
  }
}

# Restart ompweb: kills the running ompweb daemon (if any) and starts a fresh
# one on :30177. ompweb normally comes up at boot (coder_script.ompweb); this
# button is for picking up a new version or recovering a wedged process. Same
# standalone daemon as the boot script — a plain Node server that spawns omp
# directly, with no captain-miao involvement.
resource "coder_app" "restart_ompweb" {
  agent_id     = coder_agent.main.id
  slug         = "restart-ompweb"
  display_name = "Restart ompweb"
  icon         = "/icon/code.svg"
  command      = <<-EOT
    set -e
    pkill -f '@kahme247/ompweb' 2>/dev/null || true
    # Wait for the port to free before relaunching.
    i=0
    while [ "$i" -lt 10 ] && curl -sf http://localhost:30177/api/home >/dev/null 2>&1; do
      i=$((i+1))
      sleep 1
    done
    setsid nohup zsh -lc 'cd /home/dev/workspace && exec env OMP_WEB_NO_OPEN=1 npx -y @kahme247/ompweb --port 30177' >/tmp/ompweb.log 2>&1 </dev/null &
    i=0
    while [ "$i" -lt 30 ] && ! curl -sf http://localhost:30177/api/home >/dev/null 2>&1; do
      i=$((i+1))
      sleep 2
    done
    tail -n 5 /tmp/ompweb.log || true
    if curl -sf http://localhost:30177/api/home >/dev/null 2>&1; then
      echo "ompweb restarted — open the ompweb app."
    else
      echo "ompweb failed to start — see /tmp/ompweb.log"
    fi
    sleep 5
  EOT
  share        = "owner"
}

# Start opencode: launches opencode (TUI + server in one process) inside the
# miao pty pool, binding its server to loopback :4096. The phone's OpenCode web
# app and a laptop `opencode attach` both hit that same process and session
# store, so handoff (and permission approvals) work from either device.
# Uses an absolute /usr/local/bin/miao-server path inside the pooled --cmd
# (captain-miao's pty pool gives background --cmd children a minimal PATH
# that omits /usr/local/bin, so a bare `miao-server` lookup there fails) and
# exports PATH before it runs: `miao-server launch opencode` does its own
# unconditional find_in_path("opencode") internally with no override, so
# /usr/local/bin must be on PATH for that lookup too, not just for our exec.
resource "coder_app" "start_opencode" {
  agent_id     = coder_agent.main.id
  slug         = "start-opencode"
  display_name = "Start opencode"
  icon         = "/icon/terminal.svg"
  command      = <<-EOT
    set -e
    if curl -sf http://localhost:4096/global/health >/dev/null 2>&1; then
      echo "opencode is already running — open the OpenCode app."
      sleep 5
      exit 0
    fi
    miao-server daemon ensure >/dev/null
    miao-server attach opencode-web --background --dir /home/dev/workspace \
      --cmd "sh -lc 'cd /home/dev/workspace && export PATH=/usr/local/bin:\$PATH && exec /usr/local/bin/miao-server launch opencode . --hostname 127.0.0.1 --port 4096 --pool-session opencode-web'"
    echo "opencode started — open the OpenCode app."
    sleep 5
  EOT
  share        = "owner"
}

# Zellij web: mobile browser terminal, served by the boot-started zellij web
# server on loopback :8082. First visit asks for a token (see Zellij token).
resource "coder_app" "zellij_web" {
  agent_id     = coder_agent.main.id
  slug         = "zellij-web"
  display_name = "Zellij"
  icon         = "/icon/terminal.svg"
  url          = "http://localhost:8082"
  subdomain    = true
  share        = "owner"
  open_in      = "tab"

  healthcheck {
    url       = "http://localhost:8082"
    interval  = 5
    threshold = 6
  }
}

# Zellij token: shows the login token minted at boot (zellij never re-displays
# it). Copy it into the Zellij app once per device; it persists ~4 weeks.
resource "coder_app" "zellij_token" {
  agent_id     = coder_agent.main.id
  slug         = "zellij-token"
  display_name = "Zellij token"
  icon         = "/icon/terminal.svg"
  command      = "cat /home/dev/.local/share/captain-miao/zellij-web.token 2>/dev/null || echo 'no token yet — the zellij web boot script mints one next start'"
  share        = "owner"
}


# Refresh dotfiles: opens a terminal in the workspace UI and re-runs
# `coder dotfiles` to pull the latest and re-apply.
resource "coder_app" "refresh_dotfiles" {
  agent_id     = coder_agent.main.id
  slug         = "refresh-dotfiles"
  display_name = "Refresh Dotfiles"
  icon         = "/icon/dotfiles.svg"
  command      = <<-EOT
    ${local.dotfiles_sync}
    coder dotfiles "${data.coder_parameter.dotfiles_uri.value}" -y
  EOT
  share        = "owner"
}
