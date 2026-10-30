# Wiki Log

Append-only, newest last. Format: `## [YYYY-MM-DD] <kind> | <subject>`.

## [2026-10-23] add | initial structure, tofu-ci + signal-cli

- Repo seeded: `components/{tofu-ci,signal-cli}`, `hack/` build scripts,
  workflows `ci` / `publish` / `lock-refresh`, `Taskfile.yml`, `devbox.json`,
  `renovate.json`.
- tofu-ci: Wolfi has only `opentofu-1.11`/`-1.12`, so tofu 1.13.1 is built
  with melange from the upstream tag (`go-1.27`, upstream goreleaser flags).
- signal-cli: the melange key is ephemeral, passed with `--keyring-append`
  rather than listed in `apko.yaml`.
- Investigated `apko lock`/`--lockfile` with melange `@local` packages (apko
  v1.4.12): control hash enforced, signature not checked, packages missing
  from the lock silently dropped. Adopted a Wolfi-only committed lock +
  build-time merge (`hack/lockfile.py`). See
  [[troubleshooting/apko-lockfile-local-packages]].
- Toolchain moved to devbox at the maintainer's request (nixpkgs: melange
  0.59.2, apko 1.2.37, cosign 3.1.3).

## [2026-10-23] fix | ci: test step couldn't find the loaded image

- First PR run: build (melange + lock merge + apko 1.2.37) passed for both
  components; `Test image` failed with `No such image: …:build`. apko's
  tarball loads under a different tag. `hack/test.sh` now uses the name from
  `docker load` output.

## [2026-10-23] fix | publish: sign the index digest

- First publish (427a816) succeeded, but the signature, SBOM and provenance
  went on the amd64 manifest (`--image-refs`), not on the index the tags
  point to: `cosign verify ghcr.io/backend-bunny/tofu-ci@sha256:d5e2f2…`
  failed with "no signatures found"; `@sha256:652948…` (per-arch) verified.
- `hack/publish.sh` now takes the tag's digest from
  `docker buildx imagetools inspect`. Changing `hack/` republishes every
  component, so this also ships correctly signed digests.

## [2026-10-23] docs | AGENTS.md: Renovate scope

- AGENTS.md now states that Renovate owns action SHAs, `# renovate:` comments
  and image digests, never touches `apko.lock.json` (lock-refresh PR only),
  and must not automerge tofu-ci tofu bumps (matches `renovate.json`).

## [2026-10-23] docs | remove consumer-specific references

- README, component READMEs, apko.yaml comment and wiki no longer name
  consumers, clusters, the predecessor repo or the replaced upstream image;
  tofu-ci is described by its runtime contract only.

## [2026-10-23] add | standard OCI annotations

- Published images only carried apko's automatic `created`/`source`/
  `revision`. Added title, description, licenses, vendor, url and
  documentation to each `apko.yaml`, plus `image.version` from the build
  scripts; `hack/test.sh` enforces them. Lock `config.checksum` updated
  (comment/annotation-only config change, package set unchanged).

## [2026-10-23] add | download caches for melange builds

- signal-cli PR build failed: Maven Central returned 403 to the runner
  (artifact fine from elsewhere; transient IP block). Gradle and Go now keep
  their downloads in melange's `--cache-dir`, Wolfi build-env APKs go to
  `--apk-cache-dir`, and CI persists `.cache/` per component with
  `actions/cache`. See `components/build-pipeline.md` → Download caches.

## [2026-10-23] change | lock-refresh without a GitHub App; AGENTS.md refresh

- `lock-refresh` now opens its PR with `GITHUB_TOKEN` and runs `ci` on the
  branch via `workflow_dispatch` (exempt from the no-trigger rule); `ci`
  gained a `workflow_dispatch` trigger. Needs the repo setting "Allow GitHub
  Actions to create and approve pull requests". The App variable/secret are
  no longer used.
- Waiting on renovatebot/renovate#38142 (apko manager + `apko.lock.json`
  updates) before Renovate can take over lock refreshes. See
  [[decisions/lockfiles-refresh-prs]].
- AGENTS.md: removed private consumer/repo names, updated to the current
  design (Wolfi-only locks, devbox, OCI annotations, caches, index-digest
  signing).

## [2026-10-24] fix | renovate: melange version + commit in one regex span

- The Dependency Dashboard showed `opentofu/opentofu` v1.13.2 as Errored
  ("Error updating branch: update failure"). The `combination` strategy kept
  only the `expected-commit` line as the replace span, so the version could
  never be bumped.
- tofu-ci `melange.yaml`: the commit moved to `vars.expected-commit` right
  below `package.version`. `renovate.json` now uses one regex with an optional
  commit group. See `troubleshooting/renovate-update-failure.md`.

## [2026-10-24] docs | README header image

- Added `docs/assets/header.svg` (customs-declaration banner) at the top of
  `README.md`. It is a hand-written SVG with no external fonts or assets.
  Every checkbox on it must hold for every image: "pinned packages" (apko
  lockfile) and "SBOM, provenance, signature" are ticked; "Dockerfile",
  "root" and "apt" are struck. Not "shell": tofu-ci is a toolbox.

## [2026-10-24] change | lock-refresh PRs request maintainer review

- First refresh PR (#11: brotli 1.2.1-r0 → r1 in tofu-ci) needed the repo
  setting "Allow GitHub Actions to create and approve pull requests"; its
  dispatched `ci` ran green on ubuntu-26.04 runners, and a duplicate
  `pull_request` run sat awaiting approval (harmless; see build-pipeline
  gotchas).
- `create-pull-request` now sets `reviewers`/`assignees: backend-bunny`, so
  the maintainer is emailed the bump list. Merging stays manual; automerge
  options are recorded in [[decisions/lockfiles-refresh-prs]].

## [2026-10-29] add | haproxy component (Wolfi-only)

- `components/haproxy`: HAProxy 3.4 LTS (3.4.7) from Wolfi's
  `haproxy-3.4-nocaps`, with no melange. `-nocaps` avoids the file
  capability (EPERM under drop-ALL) and the bash dependency of `haproxy-3.4`.
- `hack/lib.sh` `component_version` falls back to the locked version of the
  package named by `# version-package:` in `apko.yaml` (new
  `hack/lockfile.py version`). Without it a Wolfi-only component would get
  only `sha-*` tags. See [[components/build-pipeline]].
- Local check: lock + apko build passed and the publish dry run printed
  `3.4.7`, `3.4.7-20261029`, `sha-*`. `task test -- haproxy` passed in a
  regular shell (version, features, no shell, `-c`, live frontend + admin
  socket, all with `--cap-drop ALL`). In the agent session Docker wasn't
  reachable and unix sockets are blocked, so only a bwrap rootfs run worked
  there.

## [2026-10-29] change | direnv `.envrc`

- Committed `.envrc` (`eval "$(devbox generate direnv --print-envrc)"`):
  `direnv allow` loads the devbox toolchain on `cd`. Noted in `README.md`
  and [[decisions/devbox-toolchain]].

## [2026-10-29] incident | tofu-ci lock drift (lmdb)

- haproxy PR CI failed in `build (tofu-ci)`: `not in lock: lmdb (x86_64)`.
  Wolfi rebuilds since #13 added `lmdb` to tofu-ci's resolved set. The
  haproxy PR changes `hack/`, so every component was rebuilt. Fix:
  dispatch `lock-refresh`, merge, then rebase. Gotcha added to
  [[components/build-pipeline]].

## [2026-10-29] change | licensing quick fixes

- Repo licensed Apache-2.0 (`LICENSE`, canonical text from apache.org).
- signal-cli: `copyright:` in `melange.yaml` (GPL-3.0-only; AGPL-3.0-only
  for the libsignal-client jar; GPL-2.0-only WITH Classpath-exception-2.0
  for `jre/`), and the same three in the `licenses` annotation (relocked).
- README Licenses section (SBOM query, source pointers, unofficial-build /
  trademark notice) and a License section per component README.
- Not done yet: our own source bundles and license texts in the images. See
  [[decisions/licensing]].
