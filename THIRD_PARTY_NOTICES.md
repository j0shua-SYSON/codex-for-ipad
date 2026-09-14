# Third-party notices

CodexPad combines the following open-source projects. Exact build revisions are recorded in `Dependencies/upstreams.json`.

## iSH

- Source: https://github.com/ish-app/ish
- License: GNU GPLv3, with additional terms and the iOS distribution permission in `LICENSE.md` and `LICENSE.IOS`
- Local modifications: the public source of this complete derivative app is available at https://github.com/j0shua-SYSON/codex-for-ipad

## OpenAI Codex

- Source: https://github.com/openai/codex
- License: Apache License 2.0
- The exact upstream `LICENSE` file is copied to `/usr/local/share/licenses/codex/LICENSE` in the guest runtime.

## Alpine Linux packages

- Source and package metadata: https://www.alpinelinux.org/
- Package-specific license metadata remains installed in the Alpine package database.

## Rust standard library

- Source: https://github.com/rust-lang/rust/tree/59807616e1fa2540724bfbac14d7976d7e4a3860
- Licensed under MIT or Apache-2.0. The MIT notice is reproduced below.
- Local change: the guest-only process-launch patch is published in `patches/rust-1.95-ish-spawn.patch`; see `compat/README.md` for the pinned build recipe.

Copyright (c) The Rust Project Contributors

Permission is hereby granted, free of charge, to any
person obtaining a copy of this software and associated
documentation files (the "Software"), to deal in the
Software without restriction, including without
limitation the rights to use, copy, modify, merge,
publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software
is furnished to do so, subject to the following
conditions:

The above copyright notice and this permission notice
shall be included in all copies or substantial portions
of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF
ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED
TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT
SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR
IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.

CodexPad is an independent community project. OpenAI, Codex, iSH, Apple, iPad, and iPadOS are names or marks of their respective owners.
