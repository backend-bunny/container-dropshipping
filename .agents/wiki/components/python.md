---
title: python and python-dev images
category: component
tags: [python, cpython, melange, distroless, toolbox]
---

# python / python-dev images

CPython 3.15 as two images modelled on Chainguard's `python:latest` and
`python:latest-dev`: a distroless runtime and a build toolbox.

## Key Facts

- Configs: `components/python/{melange.yaml,apko.yaml,apko.lock.json,test.sh}`
  and `components/python-dev/{apko.yaml,apko.lock.json,test.sh}`;
  `components/python-dev/melange.yaml` is a **symlink** to python's.
- CPython **3.15.2** from tag `v3.15.2` (`expected-commit: 5e58eaad…`, the
  peeled commit of the annotated tag, same form Renovate writes for tofu).
- Package names as in Wolfi: `python-3.15` (python/python3/pydoc3 links),
  `python-3.15-base` (interpreter, stdlib, libpython, pyconfig.h),
  `python-3.15-dev` (headers, python3-config, pkg-config, config-3.15 dir).
  Wolfi's `py3.15-pip`/`py3.15-setuptools` depend on `cmd:python3.15` /
  `python-3.15-base` and install on top of ours.
- python: `python-3.15@local` + `ca-certificates-bundle`, entrypoint
  `/usr/bin/python`, `HOME=/home/nonroot`, `SSL_CERT_FILE` set (as Chainguard).
- python-dev: adds `python-3.15-dev@local`, py3.15-pip, py3.15-setuptools,
  uv, bash, busybox, build-base, git; `/tmp` 1777. Toolbox exception.

## Why melange, not Wolfi

On 2026-10-31 Wolfi's `python-3.15` was `3.15.1_git20261024`, built from
the 3.15 **branch** (its `update:` says security fixes aren't tagged), while
upstream had tagged v3.15.2. A branch snapshot can't be pinned to a release
or tracked by Renovate, so the tag is built here.

Chainguard's `python:latest-dev` (amd64, 2026-10-31) contained:
apk-tools bash build-base busybox git py3.15-pip py3.15-setuptools
python-3.15-dev uv wget (+ deps), env `PATH` + `SSL_CERT_FILE`, user 65532.
Ours drops apk-tools (runs as 65532, packages go in apko.yaml) and wget
(busybox has one).

## Build choices

- Wolfi's default-variant configure flags (`--enable-optimizations
  --with-lto`, shared, system expat/libffi/mpdecimal,
  `--with-wheel-pkg-dir=/usr/share/python-wheels`). No free-threading, JIT,
  tkinter, IDLE or tests; pyc precompiled with `unchecked-hash`.
- **OpenSSL 4.0 without Wolfi's patches.** v3.15.2's `_ssl.c` already has
  `OPENSSL_VERSION_NUMBER >= 0x40000000L` guards. Wolfi's 0006/0007 patches
  only restore the deprecated `PROTOCOL_TLSv1*` constants and adjust
  test_ssl. Its FIPS patches (blake2/hmac refusal) are also not applied.
- PGO + LTO make the build slow (tens of minutes on a 4-core runner), and
  CI builds it twice when both components are selected (one job each).

## Renovate

`datasource=github-tags depName=python/cpython`, `allowedVersions <3.16.0`:
a minor bump renames every package (`python-3.16`, `py3.16-pip`, paths in
melange.yaml), so it's manual. A rule disables the python-dev symlink path so
only the real file is edited.

## Gotchas

- **An `@local` package never satisfies an untagged dependency** (go-apk,
  apko 1.2.37), even after it was selected. python-dev's first `apko lock`
  failed with "we already selected python-3.15-base=3.15.1_git… which
  conflicts with python-3.15-base=3.15.2-r0": py3.15-pip's
  `python-3.15-base`/`cmd:python3.15` deps went to Wolfi. Fix in
  python-dev's `apko.yaml`: pin `python-3.15-base@local` explicitly **and**
  list `./packages` a second time untagged. The pins select ours by name
  (Wolfi's are then "disqualified"), the untagged entry lets Wolfi packages
  depend on them. Untagged alone would pick whichever version is highest,
  and Wolfi's `3.15.2_git…` will sort above our `3.15.2`. See
  [[troubleshooting/apko-lockfile-local-packages]].

- **Symlinked melange.yaml:** `hack/discover.sh` selects a component whose
  symlink target changed. `component_version`, melange and `hashFiles` read
  through the link.
- `pip install` of a local dir builds in-tree; python-dev's test copies the
  source to `/tmp` first. Use `--system-site-packages` (or build isolation
  with an index) to get setuptools into a venv.
- Venvs hard-code their path: create them in python-dev at the path they'll
  have in the runtime image.
