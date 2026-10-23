# tofu-ci

CI image for the OpenTofu jobs in `DetBlirBaraKnas/nix-hosts` (gitlab.com),
run by the Kubernetes-executor runner on the `foundation` cluster in a
namespace with `restricted` Pod Security. Replaces
`ghcr.io/opentofu/opentofu:1.13.1` (root, Alpine 3.20/EOL).

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
It has **no entrypoint** (`cmd: /bin/sh`): GitLab overrides it, and nix-hosts
sets `entrypoint: [""]`.

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
