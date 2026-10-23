---
title: apko --lockfile with melange-built @local packages
category: troubleshooting
tags: [apko, melange, lockfile]
date: 2026-10-23
---

# apko `--lockfile` with melange-built `@local` packages

## Question

Our `@local` APKs are re-signed with a throwaway key on every build. Does
`apko build --lockfile` reject them when the lock was generated from an
earlier build?

## Experiment (apko v1.4.12, melange v0.63.1)

A trivial package `lockprobe-1.0.0-r0` built three times: pk1 (key 1), pk2
(key 2, same content), pk3 (key 2, different file content). Lock generated
against pk1, then `apko build --lockfile` with a **cold** `--cache-dir`.

| Build | Result |
|-------|--------|
| pk2: re-signed, same content | **accepted** (signature not checked against the lock) |
| pk3: same version, different content | **rejected**: `package "lockprobe" control hash mismatch` |
| lock without the local entry (config still lists it) | **built, package silently omitted** |
| config without it + `--package-append lockprobe` | **built, package silently omitted** |

Also:

- `apko lock` must be able to *see* the local packages (`nothing provides
  "<pkg>"` otherwise), so locking requires a melange build first.
- Re-locking a re-signed package rewrites its signature checksum and byte
  ranges, so the committed lock would churn on every build.
- With a **warm** apko cache, a build served the *locked* (old) APK from cache
  instead of the new one. Use a cold cache when probing.
- The `--keyring-append` key is not recorded in the lock. The config's
  sha256 is (`config.checksum`).

## Why the local entries can't simply be committed

`--lockfile` pins the local APK's control hash, i.e. its exact bytes.
melange writes the repo's HEAD commit into `.PKGINFO` (`--git-commit`
defaults to detecting HEAD), so every commit changes that hash. Gradle/jlink
output isn't guaranteed reproducible either. A committed local entry would
be stale on every PR.

## Workaround (in use)

- **Committed lock = Wolfi packages only** (`hack/lockfile.py strip`).
- **Build:** melange build → `apko lock` fresh → `hack/lockfile.py merge`
  writes `out/<c>/build.lock.json` = fresh local entries + committed Wolfi
  entries, in fresh install order. It fails if `apko.yaml`'s checksum differs
  from the lock's, or the Wolfi package-name sets differ. That check is ours,
  because apko silently drops packages missing from a lock.

## Lessons Learned

1. `--lockfile` means "install exactly this list". It isn't only a version
   constraint, and it never adds packages the lock doesn't name.
2. Probe apko behaviour with a cold `--cache-dir`.
3. Re-check with each apko bump: the toolchain (devbox) currently ships an
   older apko (1.2.37) than the one probed. CI exercises the same path.
