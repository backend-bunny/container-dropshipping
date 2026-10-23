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

### How the refresh PR gets CI

`lock-refresh` opens the PR with the workflow's `GITHUB_TOKEN` (`pr` job:
`contents`, `pull-requests`, `actions: write`). Events from `GITHUB_TOKEN`
don't start other workflows, except `workflow_dispatch`. So after opening or
updating the PR, the job runs `gh workflow run ci.yml --ref chore/lock-refresh`.
`ci`'s check runs (incl. `ci-ok`) land on the PR's head commit and gate the
merge like any PR. Without a PR base, `ci` builds every component.

Requires the repo setting **Settings → Actions → General → "Allow GitHub
Actions to create and approve pull requests"**.

A GitHub App token (PR events trigger normally) was the first design, but it
needs an App plus a private-key secret. Dispatching needs neither.

### Why not Renovate?

Renovate has no apko manager yet. **We are waiting on
[renovatebot/renovate#38142](https://github.com/renovatebot/renovate/pull/38142)**
(draft, open since 2025-09), which adds an `apk` datasource and an `apko`
manager that also updates `apko.lock.json`. When it lands, check:

1. how it relocks configs with `@local` repositories. `apko lock` fails
   ("nothing provides …") unless the melange-built APKs exist, and
   `hack/lock.sh` builds them first;
2. whether its lock output keeps our Wolfi-only convention
   (`hack/lockfile.py strip`).

If both work out, Renovate can replace `lock-refresh`. Otherwise keep the
workflow and let Renovate handle versions only.

## Consequences

- "No CVE baggage" holds only if refresh PRs are merged promptly.
- A Wolfi change to a package's *dependency set* (e.g. a new versioned
  `glibc-2.xx` name) makes `ci` fail on unrelated PRs until the refresh PR
  (or `task lock`) lands. The error says so.
- Lock refresh builds melange packages (so apko can resolve their runtime
  deps), so it takes about as long as a build.
