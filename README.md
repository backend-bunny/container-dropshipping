<p align="center">
  <img src="docs/assets/header.svg" alt="container-dropshipping: a customs declaration for container images. Contents: pinned packages, SBOM, provenance and signature; no Dockerfile, root or apt. Cleared, cosign verified." width="100%">
</p>

# container-dropshipping

Upstream tools, dropshipped: repackaged into minimal, non-root Wolfi images
with [melange](https://github.com/chainguard-dev/melange) and
[apko](https://github.com/chainguard-dev/apko). No Dockerfiles, signed with
keyless cosign, published to GHCR.

## Components

| Component | Image | What | Shell? |
|-----------|-------|------|--------|
| [`tofu-ci`](components/tofu-ci/README.md) | `ghcr.io/backend-bunny/tofu-ci` | OpenTofu 1.13.1 + age/curl/jq/git/ssh for GitLab CI jobs | yes (toolbox exception) |
| [`signal-cli`](components/signal-cli/README.md) | `ghcr.io/backend-bunny/signal-cli` | Signal messenger CLI / JSON-RPC daemon | no (distroless) |
| [`haproxy`](components/haproxy/README.md) | `ghcr.io/backend-bunny/haproxy` | HAProxy 3.4 LTS load balancer (Wolfi package, no melange) | no (distroless) |

Every image runs as uid/gid **65532** and is built for `x86_64` only.

Tags: the upstream version (`1.13.1`), `<version>-<YYYYMMDD>` and
`sha-<commit>`. **Pin by digest.**

## Verify an image

Every published digest is signed keylessly by this repo's `publish` workflow
and carries an SPDX SBOM and SLSA build provenance:

```sh
IMAGE=ghcr.io/backend-bunny/tofu-ci@sha256:...

cosign verify "$IMAGE" \
  --certificate-identity-regexp '^https://github.com/backend-bunny/container-dropshipping/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com

cosign verify-attestation "$IMAGE" --type spdxjson \
  --certificate-identity-regexp '^https://github.com/backend-bunny/container-dropshipping/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com

gh attestation verify "oci://$IMAGE" --owner backend-bunny
```

## How it builds

```
components/<name>/melange.yaml ──melange──▶ APKs signed with a throwaway key
                                                   │
components/<name>/apko.yaml ─┐                     ▼
components/<name>/apko.lock.json ──apko build --lockfile──▶ image + SBOM
                                                   │
                     (main only) apko publish ─▶ cosign sign + attest
```

- **Ephemeral melange keys:** each build runs `melange keygen`, signs the APKs,
  deletes the private key, and gives apko the public half. No key is stored
  anywhere. Image trust comes from cosign.
- **Workflows:** `ci` (PRs: build + test + lock check for changed components,
  `contents: read` only), `publish` (push to `main`: build, test, push, sign,
  attest), `lock-refresh` (weekly: open a PR with new lockfiles).
- Components are discovered from `components/*/apko.yaml`: adding a
  component means adding a directory.

## Lockfiles and refreshes

Each component commits `apko.lock.json`, and every build uses it, so a given
commit installs exactly the reviewed Wolfi package versions and checksums.

- The lock covers **Wolfi packages only**. Packages built here by melange are
  rebuilt every time (and their hash changes with every commit), so at build
  time they are merged in fresh. See
  [the wiki](.agents/wiki/troubleshooting/apko-lockfile-local-packages.md).
- CI fails if `apko.yaml` changed without a relock, or if the packages it
  resolves no longer match the lock. Fix: `task lock -- <name>` in the same PR.
- `lock-refresh` runs every Monday (and on demand). It re-locks every
  component and opens or updates **one** PR, `chore/lock-refresh`, listing the
  package bumps. It then dispatches `ci` on that branch (PRs pushed with
  `GITHUB_TOKEN` don't trigger CI on their own), so it's tested like any PR;
  **merging it publishes** the updated images. The PR requests review from
  the maintainer, who gets an email with the bump list and merges it by hand. Renovate doesn't manage apko
  lockfiles yet. We're waiting on
  [renovatebot/renovate#38142](https://github.com/renovatebot/renovate/pull/38142). Images only pick up Wolfi security fixes when these PRs are
  merged.

## Dependency updates

[Renovate](https://docs.renovatebot.com/) (Mend GitHub App) handles:

- upstream versions via `# renovate:` comments in `melange.yaml`
  (OpenTofu minor/major bumps need Dependency Dashboard approval),
- the toolchain in `devbox.json`/`devbox.lock`,
- GitHub Actions, pinned by commit SHA.

## Local development

Tools (melange, apko, cosign, task, bubblewrap, ...) are pinned in
`devbox.json`/`devbox.lock`, the same set CI installs. With
[direnv](https://direnv.net/), `direnv allow` once and the committed
`.envrc` loads the devbox environment on `cd`; otherwise run `devbox shell`.

```sh
devbox shell                     # or: direnv allow
task build -- tofu-ci            # melange build + test, apko build from lock
task test -- tofu-ci             # + smoke test in Docker
task publish-dry-run -- tofu-ci  # + print the tags CI would push
task lock -- tofu-ci             # regenerate the lockfile
task lock:all
```

Downloads (Gradle/Go dependencies, Wolfi build-environment APKs) are cached
in `.cache/` (gitignored) and reused across builds; CI persists the same
directory per component.

melange needs unprivileged user namespaces (bubblewrap). On Ubuntu 24.04:
`sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0`.

Operational notes and decisions live in [`.agents/wiki/`](.agents/wiki/index.md).

## Licenses

The configs and scripts in this repository are licensed under
[Apache-2.0](LICENSE). The images are not: each one redistributes upstream
software under that software's own license, unchanged in function.

- `org.opencontainers.image.licenses` names the licenses of the image's main
  software (e.g. `GPL-2.0-or-later` for haproxy).
- Every package in an image, with its license, is listed in the image's
  SPDX SBOM attestation:

  ```sh
  cosign verify-attestation "$IMAGE" --type spdxjson \
    --certificate-identity-regexp '^https://github.com/backend-bunny/container-dropshipping/' \
    --certificate-oidc-issuer https://token.actions.githubusercontent.com \
    | jq -r '.payload | @base64d | fromjson | .predicate.packages[]
             | "\(.name)\t\(.licenseDeclared)"' | sort -u
  ```

- Source: every image carries a **source manifest** attestation that lists,
  for each package, its upstream source pinned to a commit or checksum, an
  archived tarball where one exists, and the build recipe. It also lists
  third-party code bundled inside a package (e.g. signal-cli's Maven jars and
  its Java runtime). It is generated from the SBOM by
  [`hack/sources.py`](hack/sources.py), and builds fail if any source is
  unpinned:

  ```sh
  cosign verify-attestation "$IMAGE" \
    --type https://github.com/backend-bunny/container-dropshipping/sources/v1 \
    --certificate-identity-regexp '^https://github.com/backend-bunny/container-dropshipping/' \
    --certificate-oidc-issuer https://token.actions.githubusercontent.com \
    | jq -r '.payload | @base64d | fromjson | .predicate
             | (.packages[] | .package as $p | .sources[] | "\($p)\t\(.url)\t\(.ref)\t\(.archive)"),
               (.bundled[] | "\(.name)@\(.version)\t\(.source)\t\(.ref // "")")'
  ```

  Packages built here come from the upstream tag and commit named in the
  component's `melange.yaml`. Wolfi packages are built by the recipes in
  [wolfi-dev/os](https://github.com/wolfi-dev/os), and Chainguard keeps
  content-addressed copies of most of their sources on `tarballs.cgr.dev`.

- License texts and notices: a **notices** attestation carries, for every
  package and bundled component, the license and notice files from its
  source (`COPYING`, `LICENSE`, `NOTICE`, … at the top of the pinned source
  archive, or inside the jar), plus the canonical SPDX text of each declared
  license. It is generated by [`hack/notices.py`](hack/notices.py). The
  images themselves stay minimal. To print a package's texts:

  ```sh
  cosign verify-attestation "$IMAGE" \
    --type https://github.com/backend-bunny/container-dropshipping/notices/v1 \
    --certificate-identity-regexp '^https://github.com/backend-bunny/container-dropshipping/' \
    --certificate-oidc-issuer https://token.actions.githubusercontent.com \
    | jq -r --arg pkg haproxy-3.4-nocaps '.payload | @base64d | fromjson | .predicate as $n
             | ($n.packages + $n.bundled)[] | select((.package // .name) == $pkg)
             | .files[] | "==> \(.path)\n\($n.texts[.sha256])"'
  ```

  Where a source ships no notice file, only the canonical text is included.
  The CI job summary lists those cases.

These are **unofficial builds**, not affiliated with or endorsed by the
upstream projects. HAProxy, OpenTofu, Signal and other names are trademarks
of their respective owners and are used here only to say what an image
contains.

Besides its main software, every image contains other packages (glibc,
OpenSSL, and their dependencies), each under its own license. As with any
pre-built image, it is your responsibility to make sure that your use of an
image complies with the licenses of all the software it contains. The
images are provided as is, without warranty: see each license.
