#!/usr/bin/env bash
set -euo pipefail

: "${CARGO_TARGET_DIR:?CARGO_TARGET_DIR must point to workspace storage}"

cargo zigbuild \
  --locked \
  --release \
  --target i686-unknown-linux-musl \
  -p codex-app-server \
  --bin codex-app-server
