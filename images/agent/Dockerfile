# Kelos agent container — omp run unattended as a Kelos task pod.
# Layers on whichever language image bake points the `base` context at (the
# agent layer itself is language-independent).
# Dotfiles are NOT baked in: the image is agnostic to any particular dotfiles
# setup, and kelos_entrypoint.sh applies them at pod start from DOTFILES_URI.
# Kelos overrides ENTRYPOINT with /kelos_entrypoint.sh and sets WorkingDir to
# the cloned repo; it does NOT set RunAsUser on the agent container, so the USER
# directive at the bottom is what pins the runtime UID.
# Contract: https://github.com/kelos-dev/kelos/blob/main/docs/agent-image-interface.md

ARG BASE=base

FROM ${BASE}

USER root

# Kelos runs the git-clone init container and the agent container as the same
# UID (AgentUID) so both can read and write the workspace without ownership
# fixups — see "User ID" in the Kelos interface doc linked at the top.
RUN groupadd --gid 61100 agent \
    && useradd --uid 61100 --gid 61100 --shell /bin/bash --create-home agent \
    && mkdir -p /home/agent/.local/bin \
    && chown -R agent:agent /home/agent

ENV HOME=/home/agent \
    NPM_CONFIG_PREFIX=/home/agent/.local \
    PATH="/home/agent/.local/bin:${PATH}"

# The language images pin their mutable state under /home/dev — MIX_HOME, HEX_HOME,
# CARGO_HOME, NPM_CONFIG_PREFIX — and create it owned by dev (UID 1000) beneath a
# 0700 /home/dev. The agent runs as 61100 and cannot even traverse that, so every
# tool that installs into those paths fails: `mix local.hex` dies with EACCES on
# /home/dev/.mix/archives, and `cargo build` on any crate with a dependency dies
# with "failed to create directory /home/dev/.cargo/registry/cache". Hand the
# directory to the agent instead of re-pointing each variable here: a per-language
# list is one the next language image silently invalidates, whereas anything a
# language image puts under /home/dev keeps working and keeps its content. The
# mode needs no change — the owner of a 0700 directory can traverse and write it.
RUN chown -R agent:agent /home/dev

# Print mode exits 1 if a configured MCP server is still pending or has failed,
# rather than running the first turn without it (OMP_MCP_REQUIRE_READY, and
# "Headless/SDK" in mcp-runtime-lifecycle.md), so a missing server fails loudly
# instead of silently going missing.
ENV OMP_MCP_REQUIRE_READY=1

# Kelos runs this exact path with the task prompt as $1, overriding ENTRYPOINT.
COPY images/agent/kelos_entrypoint.sh /kelos_entrypoint.sh
RUN chmod 0755 /kelos_entrypoint.sh \
    && chown -R agent:agent /home/agent

# Kelos sets WorkingDir to the cloned repo; this is the fallback when no
# workspace is configured.
WORKDIR /home/agent

# Numeric UID, not the name: Kelos sets RunAsUser on the init containers only,
# so this directive is what makes the agent process run as AgentUID 61100.
USER 61100
