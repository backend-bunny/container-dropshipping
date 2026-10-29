---
title: haproxy image
category: component
tags: [haproxy, wolfi-only, distroless, load-balancer]
---

# haproxy image

[HAProxy](https://www.haproxy.org/) 3.4 LTS, taken directly from Wolfi as a
distroless, non-root image. It is the first component with **no
melange.yaml**.

## Key Facts

- Configs: `components/haproxy/{apko.yaml,apko.lock.json,test.sh}`
- Package: `haproxy-3.4-nocaps` (Wolfi). Streams 3.2/3.3/3.4 existed on
  2026-10-29; 3.4 is the current LTS.
- Entrypoint `/usr/bin/haproxy -W -db`, cmd `-f /etc/haproxy/haproxy.cfg`;
  no config shipped (mount one).
- Writable state dir: `/var/lib/haproxy` (uid 65532).
- Version: the locked version of the package named by the `# version-package:`
  comment in `apko.yaml` (see [[components/build-pipeline]]). Patch releases
  come through the lock-refresh PR; Renovate doesn't track this component.

## Gotchas

- **Use `-nocaps`.** `haproxy-3.4` sets `cap_net_bind_service` as a file
  capability. When a pod drops ALL caps (restricted PSS), exec of a binary
  whose file caps aren't in the bounding set fails with `EPERM`. It also
  depends on `cmd:bash` (`haproxy-reload`, `haproxy-dump-certs` scripts),
  which would put a shell in the image. `-nocaps` ships only `/usr/bin/haproxy`.
- **Ports ≥ 1024** as a consequence (unless `ip_unprivileged_port_start` is
  lowered by the runtime).
- **Stream bumps are manual:** moving to 3.6 means editing the package name and
  the `# version-package:` comment and relocking. Nothing automates that.
- **Unix sockets in a sandboxed agent session:** Claude Code's sandbox blocks
  AF_UNIX socket creation, so a local bwrap run of the test config fails on
  `stats socket` with "Operation not permitted". That is not an image bug.
  Docker isn't reachable there either. CI runs the full `test.sh`.
- `global.maxconn` defaults from `ulimit -n`; set it explicitly.
