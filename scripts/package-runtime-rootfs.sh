#!/usr/bin/env bash
set -euo pipefail

: "${CODEX_BINARY:?CODEX_BINARY must point to the i686 app-server}"
: "${OUTPUT_ROOTFS:?OUTPUT_ROOTFS must name the output archive}"

project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
artifacts_dir="$project_root/artifacts"
temporary_parent="$artifacts_dir/tmp"
mkdir -p "$temporary_parent" "$(dirname -- "$OUTPUT_ROOTFS")"

work_dir="$(mktemp -d "$temporary_parent/runtime-rootfs.XXXXXX")"
case "$work_dir" in
    "$temporary_parent"/*) ;;
    *) echo "Refusing unsafe temporary path: $work_dir" >&2; exit 1 ;;
esac
trap 'rm -rf -- "$work_dir"' EXIT

root_dir="$work_dir/root"
base_archive="$work_dir/base-rootfs.tar.gz"
mkdir -p "$root_dir"

rootfs_url="$(jq -r '.alpine.rootfsUrl' "$project_root/Dependencies/upstreams.json")"
codex_revision="$(jq -r '.codex.revision' "$project_root/Dependencies/upstreams.json")"
ish_revision="$(jq -r '.ish.revision' "$project_root/Dependencies/upstreams.json")"
alpine_release="$(jq -r '.alpine.release' "$project_root/Dependencies/upstreams.json")"

curl --proto '=https' --tlsv1.2 --fail --location --silent --show-error \
    "$rootfs_url" --output "$base_archive"
tar -xzf "$base_archive" -C "$root_dir"

docker run --rm --platform linux/386 \
    --volume "$root_dir:/target" \
    "alpine:$alpine_release" \
    apk --root /target --arch x86 --no-cache add \
        bash ca-certificates coreutils curl findutils git jq less \
        openssh-client patch python3 ripgrep

install -D -m 0755 "$CODEX_BINARY" \
    "$root_dir/usr/local/libexec/codexpad/codex-app-server"
install -D -m 0755 "$project_root/runtime/etc/init.d/codexpad" \
    "$root_dir/etc/init.d/codexpad"
install -D -m 0644 "$project_root/runtime/etc/profile.d/codexpad.sh" \
    "$root_dir/etc/profile.d/codexpad.sh"
install -d -m 0700 "$root_dir/root/.codex"
install -d -m 0755 "$root_dir/root/workspace" "$root_dir/var/log/codexpad"
install -d -m 0755 "$root_dir/etc/runlevels/default"
ln -s /etc/init.d/codexpad "$root_dir/etc/runlevels/default/codexpad"

install -d -m 0755 "$root_dir/usr/local/share/codexpad"
jq -n \
    --arg codexRevision "$codex_revision" \
    --arg ishRevision "$ish_revision" \
    --arg alpineRelease "$alpine_release" \
    --arg target "i686-unknown-linux-musl" \
    '{schemaVersion: 1, codexRevision: $codexRevision, ishRevision: $ishRevision, alpineRelease: $alpineRelease, target: $target}' \
    > "$root_dir/usr/local/share/codexpad/runtime.json"
sha256sum "$CODEX_BINARY" \
    > "$root_dir/usr/local/share/codexpad/codex-app-server.sha256"

tar --numeric-owner --owner=0 --group=0 -czf "$OUTPUT_ROOTFS" -C "$root_dir" .
sha256sum "$OUTPUT_ROOTFS" > "$OUTPUT_ROOTFS.sha256"
