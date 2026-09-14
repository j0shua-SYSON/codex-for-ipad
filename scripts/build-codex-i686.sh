#!/usr/bin/env bash
set -euo pipefail

: "${CARGO_TARGET_DIR:?CARGO_TARGET_DIR must point to workspace storage}"

project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
compatibility_patch="$project_root/patches/codex-i686-musl-openssl.patch"

git apply --check "$compatibility_patch"
git apply "$compatibility_patch"

# OpenSSL 3 probes 64-bit lock-free atomics on i386 through
# __atomic_is_lock_free, which Zig's musl runtime does not export. This
# upstream-supported guard selects OpenSSL's existing RWLock fallback instead.
export CFLAGS="${CFLAGS:+$CFLAGS }-DBROKEN_CLANG_ATOMICS"

cargo zigbuild \
  --locked \
  --release \
  --target i686-unknown-linux-musl \
  -p codex-app-server \
  --bin codex-app-server
