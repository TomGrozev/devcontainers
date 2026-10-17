#!/bin/bash
# Kelos entrypoint for the unattended omp agent image.
#
# Interface contract (read this before changing anything here):
#   https://github.com/kelos-dev/kelos/blob/main/docs/agent-image-interface.md
#
# Kelos sets the container command to this script and passes the task prompt as
# $1 (`Args: ["<prompt>"]`), and sets WorkingDir to /workspace/repo, so this
# script never chdirs. Custom images are launched directly rather than under the
# bundled /usr/bin/tini, so there is no init process forwarding signals for us.
#
# `set -uo pipefail` and deliberately NOT `-e`: the Kelos output markers below
# still have to be emitted when the agent fails, and the agent's exit code is
# captured and propagated by hand at the end.
set -uo pipefail

log() { printf '%s\n' "$*" >&2; }

# --- 1. Dotfiles ---------------------------------------------------------------
# The image is agnostic to any particular dotfiles setup, so the dots arrive here
# at pod start rather than in the image layer: clone DOTFILES_URI into $HOME and
# run its own install.sh, which links and copies the dotfiles into place. The
# clone lives at $HOME/dotfiles rather than a temp dir because the installer links
# ~/.omp/agent/* back into it, so it has to outlive this step. AGENT_POD=true
# selects the installer's agent-pod mode, which skips the shell and tool installs
# (zsh/oh-my-zsh/p10k, captain-miao, …) that only make sense
# in an interactive workspace. DOTFILES_URI is required and checked first: an
# unset value must fail deterministically, before the clone below and before
# every other step, instead of leaving a bare agent to run. DOTFILES_REF picks
# the ref, defaulting to the remote's default branch.
if [ -z "${DOTFILES_URI:-}" ]; then
  log 'DOTFILES_URI is required: it names the dotfiles repo to apply at pod start.'
  exit 1
fi

# `git clone --branch` cannot take a plain SHA, so fetch the ref and check out
# FETCH_HEAD.
dots_dir="$HOME/dotfiles"
git init -q "$dots_dir"
git -C "$dots_dir" remote add origin "$DOTFILES_URI"
# `set -u` without `-e` means neither of these is fatal on its own, and the
# install below would then fail with a confusing message — which reads as a
# dotfiles problem when the real cause is the network or the ref. Name the cause.
git -C "$dots_dir" fetch --depth 1 origin "${DOTFILES_REF:-HEAD}" \
  || { log "cannot fetch ${DOTFILES_REF:-the default branch} from $DOTFILES_URI"; exit 1; }
git -C "$dots_dir" checkout -q --detach FETCH_HEAD \
  || { log "cannot check out ${DOTFILES_REF:-the fetched default branch} in $DOTFILES_URI"; exit 1; }

# The dotfiles repo owns what gets installed; AGENT_POD=true is the agent-pod
# mode that skips the shell and tool installs. A non-zero exit means the agent
# would run without its config, so fail loudly and name the cause rather than
# continue into a bare agent.
AGENT_POD=true bash "$dots_dir/install.sh" \
  || { log "dotfiles install.sh (AGENT_POD=true) failed for $DOTFILES_URI${DOTFILES_REF:+ at $DOTFILES_REF}"; exit 1; }

# The installer owns the layout; these checks are the image's contract with it.
# A change on either side must surface loudly here, not silently produce a bare
# agent. Everything the agent-pod mode is expected to install is asserted.
dots_dest="$HOME/.omp/agent"
for path in AGENTS.md RULES.md config.yml agents rules extensions pairing-workflow.html; do
  [ -e "$dots_dest/$path" ] || { log "dotfiles install.sh did not produce $dots_dest/$path"; exit 1; }
done
for skill in implement walkthrough land; do
  [ -d "$dots_dest/skills/$skill" ] || { log "dotfiles install.sh did not produce $dots_dest/skills/$skill"; exit 1; }
done
[ -f "$HOME/.cc-safety-net/policy.json" ] \
  || { log "dotfiles install.sh did not produce $HOME/.cc-safety-net/policy.json"; exit 1; }
for skill in tdd code-review conventional-commit frontend-design apple-design; do
  [ -d "$HOME/.agents/skills/$skill" ] || { log "dotfiles install.sh did not produce $HOME/.agents/skills/$skill"; exit 1; }
done
# The NeuralWatt provider is an omp plugin, and the installer's plugin loop is
# skipped when `omp` is not on PATH — without the plugin the agent has no model
# to run on, so assert it landed rather than let the first model call fail.
[ -d "$HOME/.omp/plugins/node_modules/@aliou/pi-neuralwatt" ] \
  || { log "dotfiles install.sh did not install the NeuralWatt omp plugin"; exit 1; }
log "dotfiles applied from $DOTFILES_URI${DOTFILES_REF:+ at $DOTFILES_REF}"

# --- 2. Argument check ---------------------------------------------------------
# A Session runtime invokes this script with KELOS_SESSION_SETUP_ONLY=1 and no
# prompt; every other invocation is a Task and must carry the prompt.
if [ -z "${1:-}" ] && [ "${KELOS_SESSION_SETUP_ONLY:-}" != "1" ]; then
  log 'usage: kelos_entrypoint.sh <task-prompt>'
  exit 2
fi

# --- 3. Workspace setup command ------------------------------------------------
# KELOS_SETUP_COMMAND is Workspace.spec.setupCommand, JSON-encoded by the
# controller. The semantics match Kubernetes lifecycle.postStart.exec.command:
# the decoded array is passed straight to exec with NO shell interpretation, and
# a non-zero exit aborts the task before the agent ever runs.
if [ -n "${KELOS_SETUP_COMMAND:-}" ]; then
  log '---KELOS_SETUP_COMMAND_START---'
  if ! jq -e 'type == "array"' >/dev/null 2>&1 <<<"$KELOS_SETUP_COMMAND"; then
    log 'KELOS_SETUP_COMMAND is not a JSON array; refusing to guess at its shape'
    log '---KELOS_SETUP_COMMAND_FAILED---'
    exit 1
  fi
  mapfile -t setup_cmd < <(jq -r '.[]' <<<"$KELOS_SETUP_COMMAND")
  if [ "${#setup_cmd[@]}" -eq 0 ]; then
    log 'KELOS_SETUP_COMMAND decoded to an empty argv'
    log '---KELOS_SETUP_COMMAND_FAILED---'
    exit 1
  fi
  "${setup_cmd[@]}"
  setup_status=$?
  if [ "$setup_status" -ne 0 ]; then
    log "setup command failed with exit code $setup_status"
    log '---KELOS_SETUP_COMMAND_FAILED---'
    exit "$setup_status"
  fi
  log '---KELOS_SETUP_COMMAND_DONE---'
fi

# --- 4. Codebase index ---------------------------------------------------------
# Index the workspace before the agent starts so codebase-memory-mcp answers
# graph queries from the first turn instead of the agent spending turns on it.
# Runs after the setup command so generated sources are included. The binary
# comes from the dotfiles installer (installed in AGENT_POD mode too). A failed
# index degrades the agent to grep/read rather than breaking it, so it warns.
if [ -d /workspace/repo ]; then
  if codebase-memory-mcp cli index_repository '{"repo_path":"/workspace/repo"}' >&2; then
    log 'codebase-memory-mcp: /workspace/repo indexed'
  else
    log 'WARNING: codebase-memory-mcp indexing failed; the agent starts without a graph'
  fi
fi

# --- 5. Session setup only -----------------------------------------------------
# Kelos' Session runtime calls this entrypoint with KELOS_SESSION_SETUP_ONLY=1 and
# no prompt: prepare the environment (done above) and exit without starting a
# provider. This image is used for Tasks, but the contract says to honour it.
if [ "${KELOS_SESSION_SETUP_ONLY:-}" = "1" ]; then
  log 'KELOS_SESSION_SETUP_ONLY=1: environment prepared, not starting the agent'
  exit 0
fi

# --- 6. Run the agent ----------------------------------------------------------
# Print mode (`-p`) is the only headless route: there is no `omp run` or
# `omp implement` subcommand. The prompt is passed positionally; a non-TTY stdin
# would also be read to EOF as prompt text, but argv is the documented form.
# The skill is invoked by telling the model to `read skill://<name>` — that is
# the mode-independent route, since the read tool resolves skill URIs itself.
prompt="Read skill://${OMP_SKILL:-implement} and execute it end to end for the ticket below.

${1:-}"

# --approval-mode is deliberately NOT passed: the overlay at
# /etc/omp/agent-image/agent.yml sets tools.approvalMode: yolo, which an
# unattended run needs (the base config pins `write`, which stalls on anything
# outside workspace-write). The overlay also restates the catastrophic-command
# denies that yolo bypasses.
#
# No `exec` — Kelos requires the entrypoint to survive the agent so it can emit
# the output block afterwards — and no pipe, because we are not routing the
# agent's stdout through /kelos/kelos-capture (see step 7).
omp -p --no-title --max-time "${OMP_MAX_TIME:-45m}" \
  --append-system-prompt /etc/omp/agent-image/APPEND_SYSTEM.md \
  "$prompt"
AGENT_EXIT_CODE=$?

# --- 7. Emit Kelos outputs -----------------------------------------------------
# /kelos/kelos-capture is not published as a standalone artifact, so this image
# takes option 2 from the interface doc and emits the markers itself. The
# controller reads pod logs and extracts the lines between them; each line is
# `key: value` and lines without `: ` are kept in Outputs but skipped in Results.
#
# Every probe is guarded so that a missing repo, a detached HEAD or an
# unauthenticated `gh` emits nothing rather than aborting the script and losing
# the agent's exit code. `gh` resolves the repository from the cwd, which Kelos
# set to /workspace/repo.
branch="$(git -C /workspace/repo rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
if [ -n "$branch" ] && [ "$branch" != "HEAD" ]; then
  printf -- '---KELOS_OUTPUTS_START---\n'
  printf 'branch: %s\n' "$branch"
  commit="$(git -C /workspace/repo rev-parse HEAD 2>/dev/null || true)"
  [ -n "$commit" ] && printf 'commit: %s\n' "$commit"
  [ -n "${KELOS_BASE_BRANCH:-}" ] && printf 'base-branch: %s\n' "$KELOS_BASE_BRANCH"
  pr="$(gh pr list --head "$branch" --json url --jq '.[0].url' 2>/dev/null || true)"
  [ -n "$pr" ] && printf 'pr: %s\n' "$pr"
  printf -- '---KELOS_OUTPUTS_END---\n'
fi

# --- 8. Propagate the agent's exit code ----------------------------------------
exit "$AGENT_EXIT_CODE"
