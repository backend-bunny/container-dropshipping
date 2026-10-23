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
