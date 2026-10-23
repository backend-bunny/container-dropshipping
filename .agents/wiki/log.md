# Wiki Log

Append-only, newest last. Format: `## [YYYY-MM-DD] <kind> | <subject>`.

## [2026-10-23] add | initial structure, tofu-ci + signal-cli

- Repo seeded: `components/{tofu-ci,signal-cli}`, `hack/` build scripts,
  workflows `ci` / `publish` / `lock-refresh`, `Taskfile.yml`, `devbox.json`,
  `renovate.json`.
- tofu-ci: Wolfi has only `opentofu-1.11`/`-1.12`, so tofu 1.13.1 is built
  with melange from the upstream tag (`go-1.27`, upstream goreleaser flags).
- signal-cli: ported from `kitty-couple-public/repack` unchanged except that
  the melange key is no longer a committed file (ephemeral, passed with
  `--keyring-append`).
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
