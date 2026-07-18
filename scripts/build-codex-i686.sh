#!/usr/bin/env bash
set -euo pipefail

: "${CARGO_TARGET_DIR:?CARGO_TARGET_DIR must point to workspace storage}"

project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
compatibility_patch="$project_root/patches/codex-i686-musl-openssl.patch"
compatibility_sources="$project_root/compat/codex-i686/code-mode"

git apply --check "$compatibility_patch"
git apply "$compatibility_patch"
install -m 0644 \
  "$compatibility_sources/service_unavailable.rs" \
  ../code-mode/src/service_unavailable.rs
install -m 0644 \
  "$compatibility_sources/v8_init_unavailable.rs" \
  ../code-mode/src/v8_init_unavailable.rs

cargo zigbuild \
  --locked \
  --release \
  --target i686-unknown-linux-musl \
  -p codex-app-server \
  --bin codex-app-server
