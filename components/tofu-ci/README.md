# tofu-ci

Non-root CI image for OpenTofu jobs, built for GitLab CI's Kubernetes
executor in namespaces with `restricted` Pod Security.

Image: `ghcr.io/backend-bunny/tofu-ci` (pin by digest).

## Contents

| Tool | Source |
|------|--------|
| `tofu` **1.13.1** | built here with melange from the upstream `v1.13.1` tag (`expected-commit` pinned) |
| `age`, `curl`, `jq`, `git`, `ssh` (openssh-client), CA bundle | Wolfi, versions fixed by `apko.lock.json` |
| `sh` (busybox) | Wolfi; see the exception below |

**Why tofu is built, not taken from Wolfi:** Wolfi only packages
`opentofu-1.11` and `opentofu-1.12`; there is no 1.13.x. Tofu minor bumps can
rewrite state, so the version is a deliberate choice: Renovate opens tofu
minor/major bumps only on approval from the Dependency Dashboard.

## Exception: toolbox, not distroless

GitLab's executor runs job scripts through `sh`, so the image ships busybox.
It has **no entrypoint** (`cmd: /bin/sh`): GitLab overrides it (use
`entrypoint: [""]` in the job's `image:`).

## Runtime contract

- uid/gid **65532** (`nonroot`), `HOME=/home/nonroot` (owned by 65532), `/tmp` 1777.
- `/etc/gitconfig` sets `safe.directory = *`: the helper's checkout lives on a
  volume owned by another uid, which git would otherwise refuse ("dubious
  ownership"). Works with `runAsUser: 65532` + `fsGroup`.
- Not included: tailscale/iptables. Those jobs stay on root-capable runners.

## Tests

`melange test` checks `tofu version`. `test.sh` runs the image the way GitLab
does (script on stdin to `sh`, uid 65532, foreign-owned checkout mounted): it
checks `id`, each tool, a writable `HOME`, an `age` encrypt/decrypt round trip,
and `git status` in the checkout.

## License

OpenTofu is MPL-2.0; its source is the upstream tag named in `melange.yaml`.
The toolbox packages keep their own licenses (busybox and git are
GPL-2.0-only), listed per package in the image's SBOM attestation, with their
recipes in [wolfi-dev/os](https://github.com/wolfi-dev/os). This is an
unofficial build, not affiliated with the OpenTofu project.
