---
title: Build pipeline
category: component
tags: [melange, apko, cosign, github-actions, devbox, ci]
---

# Build pipeline

How `components/<name>/` becomes a signed image at `ghcr.io/backend-bunny/<name>`.

## Key Facts

- Scripts: `hack/{build,test,lock,publish,discover}.sh`, `hack/lib.sh`,
  `hack/lockfile.py`. CI and `Taskfile.yml` call the same scripts.
- Tools: `devbox.json`/`devbox.lock` (see [[decisions/devbox-toolchain]]);
  CI installs them with `.github/actions/setup-tools`.
- Outputs: `packages/` (melange APKs) and `out/<name>/` (`image.tar`,
  `build.lock.json`, `sbom-*.spdx.json`, `melange.rsa.pub`, `digest`).

## Flow (hack/build.sh)

| Step | Detail |
|------|--------|
| key | `melange keygen` in a temp dir |
| melange build | `--empty-workspace --runner bubblewrap`, signed with the temp key; private key deleted right after |
| melange test | the config's `test:` pipeline, against `./packages` + Wolfi |
| lock check | `apko lock` fresh → `lockfile.py merge` with the committed lock (fails on drift) |
| apko build | `--lockfile out/<name>/build.lock.json --keyring-append <pub>`; SBOMs to `out/<name>/` |

`hack/test.sh` then loads the tarball into Docker, checks `User` is 65532
and runs `components/<name>/test.sh`.

## Workflows

| Workflow | Trigger | Permissions | Does |
|----------|---------|-------------|------|
| `ci` | pull_request | `contents: read` | discover changed components → build, test, publish dry run; `ci-ok` is the single required check |
| `publish` | push to main, dispatch | job: `packages`, `id-token`, `attestations: write` | build, test, `apko publish` (3 tags), `cosign sign`, `cosign attest --type spdxjson`, `attest-build-provenance` |
| `lock-refresh` | Mon 05:17 UTC, dispatch | `contents: read` (PR via App token) | `hack/lock.sh` per component → one PR on `chore/lock-refresh` |

Change discovery (`hack/discover.sh BASE`): `components/<name>/**` selects
that component. `hack/`, `.github/` or `devbox.*` select all of them, as does
a missing BASE (new branch, dispatch).

Publish concurrency group: `publish-<component>-<ref>`, queued (not
cancelled).

## Gotchas

- **melange needs unprivileged user namespaces.** Ubuntu 24.04 AppArmor blocks
  them for binaries without a profile, and devbox's bwrap lives in
  `/nix/store`. `setup-tools` runs
  `sysctl kernel.apparmor_restrict_unprivileged_userns=0` (the runner VM is
  ephemeral). Chainguard's `setup-melange` instead adds a profile for
  `/usr/bin/bwrap`, which doesn't cover the nix binary.
- **Build deps are discovered iteratively** (carried over from repack): a
  from-source build can fail on a missing Wolfi package. Add it to
  `environment.contents.packages` and retry.
- **Wolfi names differ from Debian** (`libzmq3-dev` → `zeromq-dev`,
  `libcurl4-openssl-dev` → `curl-dev`). Check the index:
  `https://packages.wolfi.dev/os/x86_64/APKINDEX.tar.gz`.
- **Go builds:** `busybox` is required in build packages (the pipeline runs
  `sh`), set `GOTOOLCHAIN=local`, prefer `CGO_ENABLED=0`. The `go-1.xx`
  package must satisfy the `go` directive in upstream's `go.mod`.
- **Use `--empty-workspace`**: without it melange copies the config dir into
  the workspace and `git-checkout` clones into a non-empty dir.
- **Melange records the repo's HEAD commit** in `.PKGINFO`, so local APK
  hashes change on every commit. See [[troubleshooting/apko-lockfile-local-packages]].
- **apko keyring paths:** the ephemeral pubkey is passed with
  `--keyring-append`, never listed in `apko.yaml` (so it isn't in the lock).
  `@local ./packages` is relative to the repo root: run scripts from there.
- **Transient `apko InitKeyring` nil-pointer panic** was seen once in repack
  CI (concurrent keyring write). Retry before debugging.
- **apko tarballs don't load under the tag you gave `apko build`** (it may add
  an arch suffix such as `-amd64`). `hack/test.sh` uses the name `docker load`
  prints. First CI run failed with `No such image: …:build`.
- **Sign the index digest, not apko's `--image-refs`.** `apko publish` pushes
  an image index (the tags point at it), but `--image-refs` lists the per-arch
  manifests inside it. The first publish signed/attested the amd64 manifest,
  so `cosign verify` on the tag's digest found no signatures.
  `hack/publish.sh` now resolves the tag's digest with
  `docker buildx imagetools inspect`.
- **No shell in distroless images**: probes must be `httpGet`/`tcpSocket`.
