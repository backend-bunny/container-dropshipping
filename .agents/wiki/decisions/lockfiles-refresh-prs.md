---
title: apko lockfiles + refresh PRs
category: decision
tags: [supply-chain, apko, lockfile, renovate, wolfi]
date: 2026-10-23
---

# apko lockfiles + refresh PRs

## Context

Without a lock, every build re-resolves Wolfi, so a rebuild of an unchanged
commit can ship different packages that no one reviewed. We want:

1. a given commit to install exactly the reviewed package set,
2. Wolfi security fixes to still reach images regularly,
3. each bump to be visible, CI-tested and deliberately merged.

## Decision

- Each component commits `apko.lock.json` next to `apko.yaml`. Every build
  uses `apko build --lockfile`.
- **The committed lock contains Wolfi packages only.** melange-built `@local`
  packages are merged in at build time (`hack/lockfile.py merge`), because
  their control hash changes every commit. Details:
  [[troubleshooting/apko-lockfile-local-packages]].
- CI fails when the lock is out of step: `apko.yaml` changed (config checksum
  in the lock) or the resolved Wolfi package *names* differ from the lock.
- The lock changes only via PR: `task lock -- <c>` alongside a config change,
  or the weekly **`lock-refresh`** workflow, which opens/updates one PR
  (`chore/lock-refresh`) listing every version bump. Merging it publishes.

### Why a GitHub App token for the refresh PR?

PRs opened with `GITHUB_TOKEN` don't trigger other workflows, so `ci` would
never run on them. An App installation token does trigger them, and it's
short-lived and scoped to the repo, unlike a PAT. The workflow's own
`GITHUB_TOKEN` stays `contents: read`. The App holds the write access
(Contents + Pull requests: read & write).

Required: repo variable `LOCK_REFRESH_APP_ID`, secret
`LOCK_REFRESH_APP_PRIVATE_KEY`.

### Why not Renovate's lock maintenance?

Renovate has no apko lockfile manager.

## Consequences

- "No CVE baggage" holds only if refresh PRs are merged promptly.
- A Wolfi change to a package's *dependency set* (e.g. a new versioned
  `glibc-2.xx` name) makes `ci` fail on unrelated PRs until the refresh PR
  (or `task lock`) lands. The error says so.
- Lock refresh builds melange packages (so apko can resolve their runtime
  deps), so it takes about as long as a build.
