// docker-bake.hcl — multi-image build manifest for devcontainers
// All pinned versions live here. Dockerfiles consume them via ARG (no defaults).
// Tags and labels are composed in HCL; no metadata-action needed.

// ── Version variables ──────────────────────────────────────────────────────

variable "VERSION" {
  default = ""
}
variable "GIT_SHA" {
  default = ""
}
variable "CREATED" {
  default = ""
}

variable "ELIXIR_VERSION" {
  default = "1.20.3"
}
variable "OTP_VERSION" {
  default = "28.5.0.5"
}
variable "DEBIAN_VERSION" {
  default = "trixie-20260803-slim"
}
variable "TZ" {
  default = "Australia/Sydney"
}
variable "NODE_MAJOR" {
  default = "24"
}
// renovate: datasource=github-releases depName=neovim/neovim extractVersion=^(?<version>.*)$
variable "NVIM_VERSION" {
  default = "v0.12.5"
}
// renovate: datasource=github-releases depName=rtk-ai/rtk extractVersion=^(?<version>.*)$
variable "RTK_VERSION" {
  default = "v0.48.0"
}
// renovate: datasource=github-releases depName=dandavison/delta extractVersion=^(?<version>.*)$
variable "DELTA_VERSION" {
  default = "0.19.2"
}
// renovate: datasource=github-releases depName=BurntSushi/ripgrep extractVersion=^(?<version>.*)$
variable "RIPGREP_VERSION" {
  default = "15.2.0"
}
// renovate: datasource=github-releases depName=sharkdp/bat extractVersion=^v(?<version>.+)$
variable "BAT_VERSION" {
  default = "0.26.1"
}
// renovate: datasource=github-releases depName=anomalyco/opencode extractVersion=^v(?<version>.+)$
variable "OPENCODE_VERSION" {
  default = "1.18.29"
}
// renovate: datasource=github-releases depName=can1357/oh-my-pi extractVersion=^v(?<version>.+)$
variable "OMP_VERSION" {
  default = "18.1.14"
}
// renovate: datasource=github-releases depName=zellij-org/zellij extractVersion=^v(?<version>.+)$
variable "ZELLIJ_VERSION" {
  default = "0.45.1"
}
// renovate: datasource=github-releases depName=oven-sh/bun extractVersion=^bun-v(?<version>.+)$
variable "BUN_VERSION" {
  default = "1.4.2"
}
// renovate: datasource=github-releases depName=sharkdp/fd extractVersion=^v(?<version>.+)$
variable "FD_VERSION" {
  default = "10.5.0"
}
// renovate: datasource=github-releases depName=hyperlogue/captain-miao extractVersion=^v(?<version>.+)$
variable "MIAO_VERSION" {
  default = "0.8.1"
}
// renovate: datasource=rust-version depName=rust
variable "RUST_VERSION" {
  default = "1.98.1"
}

// ── Target groups ──────────────────────────────────────────────────────────

group "all" {
  targets = ["base", "elixir", "rust"]
}

// ── Common args ────────────────────────────────────────────────────────────

function "common_args" {
  params = []
  result = {
    DEBIAN_VERSION   = "${DEBIAN_VERSION}"
    TZ               = "${TZ}"
    NODE_MAJOR       = "${NODE_MAJOR}"
    NVIM_VERSION     = "${NVIM_VERSION}"
    RTK_VERSION      = "${RTK_VERSION}"
    DELTA_VERSION    = "${DELTA_VERSION}"
    RIPGREP_VERSION  = "${RIPGREP_VERSION}"
    BAT_VERSION      = "${BAT_VERSION}"
    OPENCODE_VERSION = "${OPENCODE_VERSION}"
    OMP_VERSION      = "${OMP_VERSION}"
    BUN_VERSION      = "${BUN_VERSION}"
    ZELLIJ_VERSION   = "${ZELLIJ_VERSION}"
    FD_VERSION       = "${FD_VERSION}"
    MIAO_VERSION     = "${MIAO_VERSION}"
  }
}

// ── Common labels ──────────────────────────────────────────────────────────

function "common_labels" {
  params = [title, description]
  result = {
    "org.opencontainers.image.source"      = "https://github.com/TomGrozev/devcontainers"
    "org.opencontainers.image.revision"    = "${GIT_SHA}"
    "org.opencontainers.image.created"     = "${CREATED}"
    "org.opencontainers.image.version"     = "${VERSION}"
    "org.opencontainers.image.title"       = "${title}"
    "org.opencontainers.image.description" = "${description}"
  }
}

// ── Base image ─────────────────────────────────────────────────────────────

target "base" {
  dockerfile  = "images/base/Dockerfile"
  platforms   = ["linux/amd64", "linux/arm64"]
  args        = common_args()
  cache-from  = ["type=gha,scope=base"]
  cache-to    = ["type=gha,scope=base,mode=max"]

  labels = merge(
    common_labels("devcontainer-base", "Shared devcontainer base image — Debian ${DEBIAN_VERSION}"),
    {}
  )

  tags = concat(
    ["ghcr.io/tomgrozev/devcontainer-base:latest"],
    VERSION != "" ? ["ghcr.io/tomgrozev/devcontainer-base:${VERSION}"] : [],
    GIT_SHA != "" ? ["ghcr.io/tomgrozev/devcontainer-base:sha-${substr(GIT_SHA, 0, 7)}"] : [],
    ["ghcr.io/tomgrozev/devcontainer-base:debian-trixie"],
  )
}

// ── Elixir ─────────────────────────────────────────────────────────────────

target "elixir" {
  dockerfile  = "images/elixir/Dockerfile"
  platforms   = ["linux/amd64", "linux/arm64"]
  contexts    = { base = "target:base" }
  cache-from  = ["type=gha,scope=elixir"]
  cache-to    = ["type=gha,scope=elixir,mode=max"]
  args = merge(common_args(), {
    ELIXIR_VERSION = "${ELIXIR_VERSION}"
    OTP_VERSION    = "${OTP_VERSION}"
  })

  labels = merge(
    common_labels("devcontainer-elixir", "Elixir devcontainer — Elixir ${ELIXIR_VERSION}, OTP ${OTP_VERSION}"),
    {
      "dev.tomgrozev.toolchain.elixir" = "${ELIXIR_VERSION}"
      "dev.tomgrozev.toolchain.otp"    = "${OTP_VERSION}"
    }
  )

  tags = concat(
    ["ghcr.io/tomgrozev/devcontainer-elixir:latest"],
    VERSION != "" ? ["ghcr.io/tomgrozev/devcontainer-elixir:${VERSION}"] : [],
    GIT_SHA != "" ? ["ghcr.io/tomgrozev/devcontainer-elixir:sha-${substr(GIT_SHA, 0, 7)}"] : [],
    ["ghcr.io/tomgrozev/devcontainer-elixir:elixir-${regex_replace(ELIXIR_VERSION, "(\\d+\\.\\d+).*", "$1")}"],
    ["ghcr.io/tomgrozev/devcontainer-elixir:elixir-${ELIXIR_VERSION}-otp-${OTP_VERSION}"],
    VERSION != "" ? ["ghcr.io/tomgrozev/devcontainer-elixir:${VERSION}-elixir-${ELIXIR_VERSION}-otp-${OTP_VERSION}"] : [],
  )
}

// ── Rust ───────────────────────────────────────────────────────────────────

target "rust" {
  dockerfile  = "images/rust/Dockerfile"
  platforms   = ["linux/amd64", "linux/arm64"]
  contexts    = { base = "target:base" }
  cache-from  = ["type=gha,scope=rust"]
  cache-to    = ["type=gha,scope=rust,mode=max"]
  args = merge(common_args(), {
    RUST_VERSION = "${RUST_VERSION}"
  })

  labels = merge(
    common_labels("devcontainer-rust", "Rust devcontainer — Rust ${RUST_VERSION}"),
    {
      "dev.tomgrozev.toolchain.rust" = "${RUST_VERSION}"
    }
  )

  tags = concat(
    ["ghcr.io/tomgrozev/devcontainer-rust:latest"],
    VERSION != "" ? ["ghcr.io/tomgrozev/devcontainer-rust:${VERSION}"] : [],
    GIT_SHA != "" ? ["ghcr.io/tomgrozev/devcontainer-rust:sha-${substr(GIT_SHA, 0, 7)}"] : [],
    ["ghcr.io/tomgrozev/devcontainer-rust:rust-${regex_replace(RUST_VERSION, "(\\d+\\.\\d+).*", "$1")}"],
    ["ghcr.io/tomgrozev/devcontainer-rust:rust-${RUST_VERSION}"],
    VERSION != "" ? ["ghcr.io/tomgrozev/devcontainer-rust:${VERSION}-rust-${RUST_VERSION}"] : [],
  )
}
