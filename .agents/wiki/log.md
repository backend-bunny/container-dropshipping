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
