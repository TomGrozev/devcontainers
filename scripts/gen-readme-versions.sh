#!/bin/bash
# Generate the version table in README.md from docker-bake.hcl.
# Reads bake variables via docker buildx bake --print and writes between
# <!-- versions:start --> and <!-- versions:end --> markers.
set -euo pipefail

cd "$(dirname "$0")/.."

json=$(docker buildx bake elixir rust --print 2>/dev/null)
if [ -z "$json" ]; then
  echo "Error: docker buildx bake --print failed" >&2
  exit 1
fi

elixir_ver=$(echo "$json" | jq -r '.target.elixir.args.ELIXIR_VERSION // "?"')
otp_ver=$(echo "$json" | jq -r '.target.elixir.args.OTP_VERSION // "?"')
debian=$(echo "$json" | jq -r '.target.elixir.args.DEBIAN_VERSION // "?"')
rust_ver=$(echo "$json" | jq -r '.target.rust.args.RUST_VERSION // "?"')
nvim=$(echo "$json" | jq -r '.target.elixir.args.NVIM_VERSION // "?"')
node=$(echo "$json" | jq -r '.target.elixir.args.NODE_MAJOR // "?"')
rtk=$(echo "$json" | jq -r '.target.elixir.args.RTK_VERSION // "?"')
delta=$(echo "$json" | jq -r '.target.elixir.args.DELTA_VERSION // "?"')
ripgrep=$(echo "$json" | jq -r '.target.elixir.args.RIPGREP_VERSION // "?"')
bat=$(echo "$json" | jq -r '.target.elixir.args.BAT_VERSION // "?"')
opencode=$(echo "$json" | jq -r '.target.elixir.args.OPENCODE_VERSION // "?"')
omp=$(echo "$json" | jq -r '.target.elixir.args.OMP_VERSION // "?"')
gitgraph=$(echo "$json" | jq -r '.target.elixir.args.GIT_GRAPH_VERSION // "?"')

table="| Component | Version |
| --- | --- |
| Elixir | ${elixir_ver} |
| Erlang/OTP | ${otp_ver} |
| Rust | ${rust_ver} |
| Debian | ${debian} |
| Neovim | ${nvim} |
| Node.js (major) | ${node} |
| rtk | ${rtk} |
| delta | ${delta} |
| ripgrep | ${ripgrep} |
| bat | ${bat} |
| OpenCode | ${opencode} |
| omp | ${omp} |
| git-graph | ${gitgraph} |"

# Use sed to replace everything between the markers
if grep -q '<!-- versions:start -->' README.md; then
  sed -i.bak '/<!-- versions:start -->/,/<!-- versions:end -->/{
    /<!-- versions:start -->/{
      p
      r /dev/stdin
    }
    /<!-- versions:end -->/!d
  }' README.md <<< "$table"
  rm -f README.md.bak
else
  # No markers yet — append at end
  echo "" >> README.md
  echo "<!-- versions:start -->" >> README.md
  echo "${table}" >> README.md
  echo "<!-- versions:end -->" >> README.md
fi

echo "README version table updated."
