# signal-cli

[AsamK/signal-cli](https://github.com/AsamK/signal-cli), the Signal messenger
CLI and JSON-RPC/HTTP daemon, built from source into a **distroless**,
non-root image.

Image: `ghcr.io/backend-bunny/signal-cli` (pin by digest).

## Build

- Gradle (upstream wrapper) + Wolfi `openjdk-25` → `installDist`.
- `jdeps` + `jlink` produce a minimal runtime at `/usr/lib/signal-cli/jre`;
  X11/sound natives are dropped and headless AWT is baked in.
- Only the x86_64 Linux libsignal JNI library is kept.
- Version tracked by Renovate (`# renovate:` comment on `version`).

## Runtime contract

- uid/gid 65532, no shell. The entrypoint runs `java ... org.asamk.signal.Main
  --config /var/lib/signal-cli`.
- Default cmd: `daemon --http 0.0.0.0:8080` (health: `GET /api/v1/check`).
  The HTTP API has **no auth**; restrict it with a NetworkPolicy.
- `/var/lib/signal-cli` (0700, uid 65532): account state, mount a PVC.
- `/tmp` must be writable: libsignal and sqlite-jdbc extract JNI libs there.
  With `readOnlyRootFilesystem`, mount an `emptyDir` at `/tmp`.

## Tests

`melange test` runs `--version`, checks the trust store, and runs
`listAccounts` (which loads the native libs). `test.sh` re-checks those in the
image, confirms there is no shell, and waits for the daemon's health endpoint.

## License

- signal-cli: GPL-3.0-only.
- libsignal-client (bundled jar with the `libsignal_jni` native library):
  AGPL-3.0-only. It is unmodified apart from the removed non-Linux natives,
  so AGPL §13 (network use) adds nothing for operators of this image.
- The jlink'd Java runtime under `/usr/lib/signal-cli/jre`: OpenJDK,
  GPL-2.0-only WITH Classpath-exception-2.0.
- Other dependency jars in `/usr/lib/signal-cli/lib` keep their own licenses.

The image's `licenses` annotation and the melange `copyright:` block record
the three copyleft licenses above. Every Wolfi package's license is in the
SBOM attestation. Source: the upstream tag named in `melange.yaml`. This is
an unofficial build, not affiliated with Signal.
