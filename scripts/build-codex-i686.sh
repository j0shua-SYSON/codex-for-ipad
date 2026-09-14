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

# Build only the guest standard library with its reviewed, version-locked
# process-launch compatibility patch. The host compiler/std remain unchanged.
# Deliberately fail closed when an upstream Rust upgrade needs a new review.
test "$(rustc --version | cut -d ' ' -f2)" = "1.95.0"
test "$(rustc -vV | sed -n 's/^commit-hash: //p')" = "59807616e1fa2540724bfbac14d7976d7e4a3860"
rust_source="$(rustc --print sysroot)/lib/rustlib/src/rust"
# rust-src is nested inside this checkout's workspace. Without its own git
# root, git apply silently skips paths outside the current subdirectory and
# still exits zero! Isolate it and verify the actual post-patch source.
git -C "$rust_source" init --quiet
git -C "$rust_source" apply --check --verbose "$project_root/patches/rust-1.95-ish-spawn.patch"
git -C "$rust_source" apply --verbose "$project_root/patches/rust-1.95-ish-spawn.patch"
grep -Fq 'pidfd is unavailable in iSH' "$rust_source/library/std/src/sys/process/unix/unix.rs"
git -C "$rust_source" apply --reverse --check "$project_root/patches/rust-1.95-ish-spawn.patch"

# Exercise the patched standard library before the expensive full Codex build.
# This tiny ELF needs no Alpine image: it spawns itself inside the real iSH
# emulator from a worker thread and checks nonzero exit/stderr/ENOENT behavior.
RUSTC_BOOTSTRAP=1 cargo zigbuild \
  -Z build-std=std,panic_abort --locked --release \
  --target i686-unknown-linux-musl \
  --manifest-path "$project_root/tests/codexpad/spawn-smoke/Cargo.toml"
meson setup "$project_root/artifacts/spawn-ish" "$project_root" \
  -Dengine=asbestos -Dkernel=ish -Dbuildtype=debug
ninja -C "$project_root/artifacts/spawn-ish"
mkdir -p "$project_root/artifacts/spawn-guest"
install -m 0755 "$CARGO_TARGET_DIR/i686-unknown-linux-musl/release/spawn-smoke" \
  "$project_root/artifacts/spawn-guest/spawn-smoke"
timeout 30 "$project_root/artifacts/spawn-ish/ish" \
  -r "$project_root/artifacts/spawn-guest" /spawn-smoke

RUSTC_BOOTSTRAP=1 cargo zigbuild \
  -Z build-std=std,panic_abort \
  --locked \
  --release \
  --target i686-unknown-linux-musl \
  -p codex-app-server \
  --bin codex-app-server
