---
title: Toolchain pinned with devbox
category: decision
tags: [devbox, nix, melange, apko, cosign, tooling]
date: 2026-10-23
---

# Toolchain pinned with devbox

## Context

melange, apko and cosign versions affect the output (lock format, SBOMs,
signature behaviour), so CI and local builds must use the same versions.

## Decision

`devbox.json` + `devbox.lock` (nixpkgs) pin melange, apko, cosign, go-task,
bubblewrap, python3 and jq. CI installs them with
`jetify-com/devbox-install-action` (`.github/actions/setup-tools`) and runs
everything as `devbox run -- hack/...`. Developers use `devbox shell`.
Renovate's `devbox` manager proposes bumps.

### Why not Chainguard's `setup-melange` + release tarballs?

That pins the tools in two places (action input for CI, something else
locally), and `setup-melange` has no apko counterpart (`apko-build` is
deprecated and can't take `--lockfile`). devbox gives one lock for both, at
the maintainer's request.

## Consequences

- nixpkgs lags upstream (2026-10-23: melange 0.59.2 vs 0.63.1, apko 1.2.37
  vs 1.4.12). The lockfile behaviour in
  [[troubleshooting/apko-lockfile-local-packages]] was probed with apko 1.4.12
  and is re-checked by CI with the devbox versions.
- devbox's bwrap isn't covered by Ubuntu's AppArmor bwrap profile, hence the
  sysctl in `setup-tools`.
