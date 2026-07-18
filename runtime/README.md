# CodexPad guest overlay

These files are copied into the pinned Alpine x86 root filesystem by
`scripts/package-runtime-rootfs.sh`. The app-server listens only on guest
loopback and starts through OpenRC. Keep platform-specific changes here rather
than carrying a fork of the Codex Rust workspace.
