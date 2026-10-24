---
title: tofu-ci image
category: component
tags: [opentofu, ci, gitlab, toolbox, melange, go]
---

# tofu-ci image

CI image for the OpenTofu jobs in gitlab.com `DetBlirBaraKnas/nix-hosts`
(`.gitlab/ci/tofu.yml`), run by the Kubernetes-executor runner on the
`foundation` cluster under `restricted` Pod Security.

## Key Facts

- Configs: `components/tofu-ci/{melange.yaml,apko.yaml,apko.lock.json,test.sh}`
- tofu **1.13.1**, built with melange from tag `v1.13.1`
  (`expected-commit: 233700b7…`); Go from Wolfi `go-1.27`
- Extra Wolfi packages: `age busybox ca-certificates-bundle curl git jq openssh-client`
- Local subpackage `tofu-ci-gitconfig` ships `/etc/gitconfig` (`safe.directory = *`)
- uid/gid 65532, `HOME=/home/nonroot`, `/tmp` 1777, no entrypoint, `cmd: /bin/sh`
- Replaces `ghcr.io/opentofu/opentofu:1.13.1` (root, Alpine 3.20 EOL)

## Why melange, not Wolfi

On 2026-10-23 the Wolfi index had only `opentofu-1.11` (≤1.11.8) and
`opentofu-1.12` (≤1.12.1). Tofu minor bumps can rewrite state, so the
consumer needs exactly 1.13.1. The build reproduces upstream's goreleaser
flags (`-trimpath -mod=readonly`, `-ldflags "-s -w -X …version.dev=no"`),
without `officialBuild`, which is for the OpenTofu project's own releases.
If Wolfi gains a matching `opentofu-1.13`, switching to it is an option.
Melange would then no longer be needed for tofu.

Renovate: `datasource=github-tags`, which updates `version` and
`vars.expected-commit` together. Minor/major bumps need Dependency Dashboard
approval. `version` must stay the last key of `package:`, with `vars:` and
`expected-commit` directly below it, because the regex manager matches both
in one span (see `troubleshooting/renovate-update-failure.md`).

## Toolbox exception

Not distroless: GitLab's executor runs job scripts with `sh`, so busybox is
included. Documented in `components/tofu-ci/README.md`.

## Gotchas

- **git "dubious ownership"**: the GitLab helper checks the repo out into a
  build volume not owned by uid 65532. The system gitconfig trusts all
  directories. apko can't write file contents, hence the melange subpackage.
- **Writable HOME**: `/home/nonroot` is owned by 65532. If the runner ever
  uses a different `runAsUser`, set `HOME` to the build dir or `/tmp`.
- **No tailscale/iptables**: those jobs stay on root-capable runners.
