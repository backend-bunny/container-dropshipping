# python-dev

Build-time companion of [python](../python/README.md), modelled on
Chainguard's `python:latest-dev`: the same CPython 3.15 plus a shell, pip,
uv, setuptools, git and a C toolchain, for building virtualenvs that are then
copied into the distroless `python` image.

Image: `ghcr.io/backend-bunny/python-dev` (pin by digest).

## Build

`melange.yaml` is a symlink to `../python/melange.yaml`: both images ship the
identical CPython build, and a change to it rebuilds both (`hack/discover.sh`
follows the symlink). Renovate updates only the real file.

| Contents | Source |
|----------|--------|
| `python` 3.15.2 + headers (`python-3.15-dev`) | built here with melange |
| `pip`, `setuptools` (py3.15-*), `uv`, `git`, `bash`, busybox, `build-base` (gcc, make, pkgconf) | Wolfi, versions fixed by `apko.lock.json` |

## Exception: toolbox, not distroless

It ships shells and compilers so that `pip`/`uv` can build sdists and C
extensions. Use it in build stages or CI only, never as a runtime image.

Unlike Chainguard's `-dev` image there is **no `apk`**: the image runs as
65532 and can't install packages anyway. Packages belong in `apko.yaml`.

## Runtime contract

- uid/gid 65532, `HOME=/home/nonroot` (owned by 65532), `/tmp` 1777.
- Entrypoint `/usr/bin/python` (like `python`). For scripts use
  `--entrypoint /bin/sh` (or `bash`).
- System site-packages are root-owned: install into a venv
  (`python -m venv /app/venv`, `uv venv`). Create it at the path it will have
  in the runtime image.

## Tests

`test.sh` runs as 65532 with `--cap-drop ALL`: it checks the tools, builds a
small C extension into a venv with pip (offline), imports it, and creates a
venv with uv.

## License

CPython is PSF-2.0 (see [python](../python/README.md#license)). The toolbox
packages keep their own licenses (gcc, binutils, make, bash, busybox and git
are GPL), listed per package in the image's SBOM attestation, with their
recipes in [wolfi-dev/os](https://github.com/wolfi-dev/os). This is an
unofficial build, not affiliated with the Python Software Foundation.
