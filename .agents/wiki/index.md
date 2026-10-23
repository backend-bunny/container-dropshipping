# Wiki Index

Operational knowledge for **backend-bunny/container-dropshipping**. Read this
before troubleshooting; update it after every change (and append to
[log.md](log.md)).

## Components

| Page | Summary |
|------|---------|
| [components/build-pipeline.md](components/build-pipeline.md) | hack/ scripts, workflows, devbox toolchain, change discovery, publish/sign flow, download caches and gotchas |
| [components/tofu-ci.md](components/tofu-ci.md) | OpenTofu 1.13.1 CI toolbox for GitLab Kubernetes-executor jobs; tofu built with melange (not in Wolfi) |
| [components/signal-cli.md](components/signal-cli.md) | signal-cli, Gradle/JDK 25 from source, jlink-trimmed runtime, distroless |

## Decisions

| Page | Summary |
|------|---------|
| [decisions/ephemeral-melange-keys-keyless-cosign.md](decisions/ephemeral-melange-keys-keyless-cosign.md) | Throwaway melange key per build; image trust from keyless cosign + attestations |
| [decisions/lockfiles-refresh-prs.md](decisions/lockfiles-refresh-prs.md) | Committed apko lockfiles (Wolfi-only), weekly refresh PR opened by a GitHub App |
| [decisions/devbox-toolchain.md](decisions/devbox-toolchain.md) | melange/apko/cosign pinned with devbox (nixpkgs), shared by CI and local |

## Troubleshooting

| Page | Summary |
|------|---------|
| [troubleshooting/apko-lockfile-local-packages.md](troubleshooting/apko-lockfile-local-packages.md) | How `apko build --lockfile` treats melange-built `@local` packages (control hash enforced, silent drops), and the merge workaround |
