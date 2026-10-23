# Agent Guide — container-dropshipping

> Upstream tools, dropshipped: repackaged into minimal, distroless Wolfi images
> with apko & melange, with no Dockerfiles and no CVE baggage, delivered to GHCR.

This repo rebuilds upstream software into **minimal, non-root, signed OCI images**
built from **Wolfi** packages with Chainguard's **melange** (source → APK) and
**apko** (APKs → image). Images publish to `ghcr.io/backend-bunny/<component>`
and are consumed by Kubernetes clusters and CI jobs that enforce `restricted`
Pod Security. Operational knowledge lives in `.agents/wiki/`: read it first.

## Hard rules

- **No Dockerfiles.** Images are built only with apko (+ melange when a Wolfi
  package doesn't exist or can't be pinned). Never add a `Dockerfile` or
  `docker build` step.
- **Wolfi only.** Package names are Wolfi names (`packages.wolfi.dev/os`), never
  Debian/Alpine names. Check the Wolfi index before assuming a package exists.
- **Non-root, numeric UID.** Every image sets `accounts.run-as: 65532` (user and
  group `nonroot`). Consumers enforce Kubernetes `restricted` Pod Security, which
  checks a *numeric* non-root UID.
- **Distroless by default.** No shell or package manager in runtime images. The
  only exception is a **toolbox** image whose consumer needs a shell (e.g. the
  `tofu-ci` image: GitLab's executor runs job scripts through `sh`). Document
  every exception in the component's README and in the wiki.
- **melange signing keys are ephemeral.** Generate a fresh keypair per build
  (`melange keygen`) inside the job, sign the APKs with it, give apko the public
  half (`--keyring-append`, never listed in `apko.yaml`), and discard both.
  **No melange private key is ever committed, stored as a repo/org secret, or
  reused across builds.** The APK signature only has to bridge melange → apko
  within one job; image trust comes from cosign.
- **Images are signed keylessly.** cosign with GitHub Actions OIDC (Sigstore
  public-good Fulcio/Rekor). No long-lived signing keys anywhere. Sign and
  attest the **image index digest** (what the tags point to), with the SBOM
  (apko generates SPDX) and build provenance as attestations.
- **Standard OCI annotations.** Every `apko.yaml` sets
  `org.opencontainers.image.{title,description,licenses,vendor,url,documentation}`
  under `annotations:`. The build scripts add `image.version`, and apko adds
  `created`/`source`/`revision`. `hack/test.sh` fails when they are missing.
- **Pin everything.**
  - GitHub Actions by full commit SHA with the version in a trailing comment.
  - Upstream versions in `melange.yaml` with a `# renovate:` inline comment;
    when `expected-commit` is pinned, Renovate updates it with the version.
  - Build tools (melange, apko, cosign, task, bubblewrap, …) in
    `devbox.json` + `devbox.lock`, used by CI and locally. Run tools via
    `devbox run --` / `devbox shell`; don't install them any other way.
  - Wolfi packages in `apko.yaml` pinned to a version only where the consumer
    depends on it. If Wolfi doesn't carry the needed version, build it with
    melange (as `tofu-ci` does for tofu 1.13.x).
- **Every image is built from a committed apko lockfile.** Each component has
  `apko.lock.json` next to its `apko.yaml`, generated with `task lock -- <name>`
  (`hack/lock.sh`). Every build uses `apko build --lockfile`, so a build of a
  given commit installs exactly the reviewed Wolfi package set.
  - **The committed lock holds Wolfi packages only.** melange-built `@local`
    packages change their control hash on every commit, which `--lockfile`
    enforces, so `hack/lockfile.py merge` adds them fresh at build time. See
    `.agents/wiki/troubleshooting/apko-lockfile-local-packages.md`.
  - **apko installs exactly the lock's package list** and silently drops config
    packages missing from it. `hack/lockfile.py merge` is what fails CI when
    `apko.yaml` changed without a relock or the resolved package set drifted.
    Regenerate the lock in the same PR as the config change.
  - **The lock is otherwise only changed by the refresh PR**, never silently
    in CI: the scheduled `lock-refresh` workflow re-runs `apko lock` and opens
    or updates one PR. Its diff is the list of package bumps, and merging it is
    what publishes them.
- **x86_64 only** for now. All consumers are amd64; don't add `aarch64` to
  `archs` until a consumer needs it.
- **Never push to `main` directly.** `main` is protected (managed outside this
  repo): PR, linear history, no force pushes, admins included.

## Layout

```
components/<name>/
  melange.yaml      # only if built from source / not in Wolfi
  apko.yaml         # always (with OCI annotations)
  apko.lock.json    # always; Wolfi packages only, changed only via PR
  test.sh           # image smoke test (run by hack/test.sh)
  README.md         # what it is, runtime contract, any exceptions
hack/               # build/test/lock/publish/discover scripts shared by CI and Taskfile
.github/workflows/  # ci (PR), publish (main), lock-refresh (weekly PR)
.github/actions/    # setup-tools: devbox toolchain, bwrap sysctl, download cache
devbox.json/.lock   # pinned toolchain
Taskfile.yml        # local entry points (task build/test/lock/publish-dry-run)
renovate.json       # Renovate config
.agents/wiki/       # operational knowledge (index.md, log.md, components/, decisions/, troubleshooting/)
```

A component is discovered from `components/*/apko.yaml`: adding one means
adding a directory, not editing workflows.

## Publishing contract

- Image: `ghcr.io/backend-bunny/<component>`.
- Tags: the upstream version (e.g. `1.13.1`) **and** immutable
  `<version>-<YYYYMMDD>` / `sha-<short>` tags. Consumers pin by **digest**.
- Every published index digest is cosign-signed and carries SBOM + provenance
  attestations, verifiable with
  `cosign verify ghcr.io/backend-bunny/<component>@<digest> --certificate-identity-regexp '^https://github.com/backend-bunny/container-dropshipping/' --certificate-oidc-issuer https://token.actions.githubusercontent.com`.
- Packages are **public** on GHCR, so clusters pull anonymously.
- Refresh the lockfiles on a schedule (weekly at least): the refresh PR is how
  Wolfi security fixes reach published images. "No CVE baggage" depends on
  those PRs actually being merged. A rebuild against an unchanged lock ships the
  same packages.

## Dependency updates

Renovate (Mend GitHub App, enabled on this repo) owns version bumps: action
SHAs, runner images, the `# renovate:` comments in `melange.yaml`, and the
devbox toolchain, configured in `renovate.json`. Never automerge a `tofu-ci`
tofu version bump.

Renovate does **not** touch `apko.lock.json` yet: it has no apko manager.
**We are waiting on [renovatebot/renovate#38142](https://github.com/renovatebot/renovate/pull/38142)** (draft as of 2026-10-23), which adds an
`apk` datasource and an `apko` manager that can update `apko.lock.json`.
Until it lands, the `lock-refresh` workflow owns the locks. It opens the PR
with `GITHUB_TOKEN` (no App, no secret) and dispatches `ci` on the branch,
because `GITHUB_TOKEN` pushes don't trigger `pull_request` workflows. When it
lands, check how it handles our `@local` packages: `apko lock` needs the
melange-built APKs present, which `hack/lock.sh` builds first. Then decide
whether Renovate can replace `lock-refresh`.

## Builds and caches

- Gradle/Go downloads and melange's build-environment APKs are cached in
  `.cache/` (melange `--cache-dir` / `--apk-cache-dir`), persisted per
  component in CI with `actions/cache`. Point a component's language cache at
  `/var/cache/melange/...` in its `melange.yaml`.
- Never give `melange test` or apko a package cache: they must install the
  just-built local APK, not a cached one.

## Wiki

Keep `.agents/wiki/` current: after any change, update or create the relevant
component/decision/troubleshooting page, refresh `index.md`, and append a dated
entry to `log.md`. Check it before troubleshooting.

## What NOT to do

- Do not add Dockerfiles, a Docker build, or a Debian/Alpine base.
- Do not store, commit or reuse a melange signing key.
- Do not use `latest`/floating tags in workflows or consumer docs.
- Do not grant workflows more than `contents: read` by default. Elevate per job
  (`packages: write`, `id-token: write`, `attestations: write`) only where it
  publishes.
- Do not run `pull_request_target` or give PR builds publish/OIDC permissions.
- Do not name private consumers, clusters or repositories in this public repo's
  docs; describe components by their runtime contract.
