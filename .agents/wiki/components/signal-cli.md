---
title: signal-cli image
category: component
tags: [signal-cli, java, gradle, jlink, from-source, distroless]
---

# signal-cli image

Rebuilds [AsamK/signal-cli](https://github.com/AsamK/signal-cli) — CLI and
JSON-RPC/HTTP daemon for the Signal messenger — into a distroless, non-root
image built from source. Upstream ships no official container image.

## Key Facts

- Upstream: `https://github.com/AsamK/signal-cli` (tagged releases `vX.Y.Z`)
- Configs: `components/signal-cli/{melange.yaml,apko.yaml,apko.lock.json,test.sh}`
- Runtime: jlink-trimmed JDK 25 runtime bundled at `/usr/lib/signal-cli/jre`
- Default command: `daemon --http 0.0.0.0:8080` (multi-account mode)
- Health: `GET /api/v1/check` on the HTTP port (use `httpGet` probe)
- State: `/var/lib/signal-cli` (passed as `--config`; mount a PVC)
- Version tracking: Renovate via `datasource=github-tags depName=AsamK/signal-cli`,
  bumping `vars.expected-commit` with it (same layout as tofu-ci)
- Bundled sources: `/usr/share/doc/signal-cli/bundled-sources.json` (every
  runtimeClasspath Maven jar + the Wolfi `openjdk-25` that jlink trimmed), for
  [[components/build-pipeline]]'s source manifest

## Build

| Step | Detail |
|------|--------|
| Source | `git-checkout` at tag `v$version` |
| Toolchain | Wolfi `openjdk-25`; Gradle via upstream's wrapper (pinned + checksum-validated) |
| Build | `./gradlew installDist -x test` → `build/install/signal-cli/lib/*.jar` |
| Runtime | `jdeps --print-module-deps` (on module-info-stripped jar copies) + extras → `jlink` into `jre/`; GUI/sound natives deleted |
| Trim | non-Linux / `_testing_` natives zipped out of `libsignal-client-*.jar` |

The stock `openjdk-25-jre` was avoided: it pulls X11/ALSA/freetype/fonts.

## Image Layout

| Path | Content |
|------|---------|
| `/usr/lib/signal-cli/jre/` | jlink runtime |
| `/usr/lib/signal-cli/lib/` | signal-cli + dependency jars |
| `/var/lib/signal-cli/` | account data (uid 65532, 0700) |
| `/tmp` | 1777 — JNI lib extraction |

## Runtime Usage

Entrypoint ends in `--config /var/lib/signal-cli`, so k8s `args:` replace only
the subcommand, e.g. register/link a device once:

```
args: ["-a", "+46...", "link", "-n", "<device-name>"]
```

## Gotchas

- **bundled-sources.json comes from a Gradle init script** (`bundledSources`
  task, run `--offline --no-configuration-cache` after `installDist`): resolved
  `runtimeClasspath` module artifacts → Maven purl + Maven Central dir.
  libsignal-client points at `github.com/signalapp/libsignal` tag
  `v<version>` (AGPL). The JDK version comes from the build env's apk DB. If
  the task fails, check whether upstream renamed `runtimeClasspath` or
  enabled something that breaks `--offline`.

- **No shell**: upstream's `bin/signal-cli` is a shell script and is not
  shipped; the entrypoint runs `java -cp /usr/lib/signal-cli/lib/*` directly
  (the JVM expands the wildcard itself).
- **libsignal JNI is prebuilt**: `libsignal_jni_amd64.so` comes inside
  upstream's `libsignal-client` Maven jar (built by Signal), not rebuilt from
  Rust source here. signal-cli's own Java code is built from source.
- **Writable `/tmp` required**: libsignal and sqlite-jdbc extract native libs to
  `java.io.tmpdir` at startup. With `readOnlyRootFilesystem`, mount an
  `emptyDir` at `/tmp`.
- **jdeps exit 2 on the raw jars**: many deps ship `module-info.class` (rxjava3
  `requires org.reactivestreams`, micronaut split packages), which jdeps tries to
  resolve even with `--class-path` + `--ignore-missing-deps` → `Error: Module
  org.reactivestreams not found` (printed on **stdout**, so `$(...)` hid it).
  Fixed by running jdeps on scratch copies with `module-info.class` zipped out.
- **libstdc++ is an explicit runtime dep**: `libsignal_jni_amd64.so` lives inside a
  jar, so melange SCA can't see that it links `libstdc++.so.6`. Without it:
  `Missing required native library dependency: libsignal-client`. The melange
  test runs `listAccounts` to catch this (it exits 1 if the JNI lib can't load).
- **java.desktop is pulled in** (java.beans) — its X11/ALSA/freetype-linked
  natives (`libawt_xawt`, `libfontmanager`, `libjsound`, …) are deleted after
  jlink and `-Djava.awt.headless=true` is baked in, so SCA doesn't drag GUI libs in.
- **HTTP daemon has no auth**: on `localhost` it pins the Host header; on
  `0.0.0.0` (our default) validation is disabled. Restrict with a NetworkPolicy.
- **jlink module list**: jdeps misses reflective/ServiceLoader modules; extras
  (`jdk.unsupported`, `jdk.naming.dns`, `jdk.zipfs`, `jdk.crypto.cryptoki`) are
  appended. A `NoClassDefFoundError` for a `java.*`/`jdk.*` class at runtime
  means a module needs adding there.
- **Upstream needs JDK 25** (since 0.14.x). Bump the Wolfi JDK package if a
  future release raises it.
- **Ephemeral melange key**: the pubkey is passed with `--keyring-append`,
  not listed in `apko.yaml`.
