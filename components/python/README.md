# python

[Python](https://www.python.org/) 3.15 as a **distroless**, non-root runtime
image, modelled on Chainguard's `python:latest`. Its build-time companion is
[python-dev](../python-dev/README.md).

Image: `ghcr.io/backend-bunny/python` (pin by digest).

## Build

- CPython **3.15.2** is built here with melange from the upstream `v3.15.2`
  tag (`expected-commit` pinned). Wolfi's `python-3.15` builds from the 3.15
  maintenance branch and lagged the release (3.15.1 + branch fixes on
  2026-10-31), so it can't be pinned to a release.
- Renovate bumps `version` + `expected-commit` together (3.15.x only). Moving
  to 3.16 is a manual change: every package name contains the minor version.
- Same configure flags as Wolfi's default build (`--enable-optimizations
  --with-lto`, shared libpython, system expat/libffi/mpdecimal, OpenSSL 4.0
  from Wolfi). Not built: the free-threaded and JIT variants, tkinter/IDLE,
  the stdlib test suite. Bytecode is precompiled (`unchecked-hash`).
- Package split as in Wolfi (`python-3.15`, `-base`, `-dev`), so Wolfi's
  `py3.15-*` packages install on top.

## Runtime contract

- uid/gid 65532, `HOME=/home/nonroot` (owned by 65532), no shell.
- Entrypoint `/usr/bin/python`: args are passed to Python
  (`args: ["/app/main.py"]` or `["-m", "mypkg"]`).
- No pip. Build a virtualenv in `python-dev` at the path it will have here
  (venv scripts hard-code it), copy it in, and put its `bin/` first on
  `PATH`.
- `SSL_CERT_FILE` points at the Wolfi CA bundle.
- `readOnlyRootFilesystem: true` works: nothing is written at startup.
  Mount an `emptyDir` wherever the app writes (e.g. `/tmp`).

## Tests

`melange test` checks the version, the extension modules linked to Wolfi
libraries (ssl, sqlite3, zstd, lzma, decimal, …) and `venv` + pip.
`test.sh` runs with `--cap-drop ALL`, `no-new-privileges` and
`--read-only`: version, no shell, and a mounted script checking uid 65532,
the CA store, sqlite and ctypes.

## License

CPython is PSF-2.0; its source is the upstream tag named in `melange.yaml`.
Linked libraries keep their own licenses (readline and gdbm are GPL-3.0-or-later,
OpenSSL is Apache-2.0, …), listed per package in the image's SBOM
attestation, with their recipes in [wolfi-dev/os](https://github.com/wolfi-dev/os).
This is an unofficial build, not affiliated with the Python Software
Foundation.
