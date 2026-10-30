# haproxy

[HAProxy](https://www.haproxy.org/), the TCP/HTTP load balancer and reverse
proxy, as a **distroless**, non-root image. Tracks the **3.4 LTS** branch.

Image: `ghcr.io/backend-bunny/haproxy` (pin by digest).

## Build

- No melange: Wolfi's `haproxy-3.4-nocaps` package, pinned by
  `apko.lock.json`. The weekly lock-refresh PR is how 3.4.x patch releases
  arrive.
- The `-nocaps` variant is used on purpose. Plain `haproxy-3.4` sets the
  `cap_net_bind_service` file capability, so exec fails with `EPERM` when the
  pod drops ALL capabilities. It also pulls in bash for its reload helpers.
- The image version (`3.4.7`, …) is the locked version of the package named
  by the `# version-package:` comment in `apko.yaml`.
- Built with OpenSSL, Lua 5.3 and PCRE2. `ca-certificates-bundle` is included
  for `ca-file @system-ca`.

## Runtime contract

- uid/gid 65532, no shell. Entrypoint: `/usr/bin/haproxy -W -db`
  (master-worker, foreground, logs on stderr).
- Default cmd: `-f /etc/haproxy/haproxy.cfg`. **The image ships no config**:
  mount one (ConfigMap/Secret) at `/etc/haproxy/`. Override `args:` to pass
  several `-f` files or a directory.
- **Listen on ports ≥ 1024** (e.g. 8080/8443), unless the runtime sets
  `net.ipv4.ip_unprivileged_port_start` lower. There is no capability to
  bind low ports.
- `/var/lib/haproxy` (0750, uid 65532): put the stats/admin socket and
  server-state files here. Every other path is read-only-safe, so
  `readOnlyRootFilesystem: true` works as long as this directory is an
  `emptyDir`.
- Reload: send `SIGUSR2` to PID 1 (the master), for example after a mounted
  ConfigMap changes. No shell or `haproxy-reload` script is needed.
- Probes: `httpGet`/`tcpSocket` against a frontend (e.g. an
  `http-request return status 200` monitor frontend). There's no shell for
  `exec` probes.
- Set `global.maxconn` explicitly. Otherwise HAProxy derives it from the
  file-descriptor limit, which can be very high in containers.

## Tests

`test.sh` runs with `--cap-drop ALL` and `no-new-privileges`. It checks
`-v` against the locked version and `-vv` for OpenSSL/Lua/PCRE2, confirms
there is no shell, validates a config with `-c`, and then serves a live HTTP
frontend that also binds an admin socket in `/var/lib/haproxy`.

## License

HAProxy is GPL-2.0-or-later. Its libraries (glibc, OpenSSL, Lua, PCRE2, …)
keep their own licenses, listed per package in the image's SBOM attestation.
Source: Wolfi's `haproxy-3.4` recipe in
[wolfi-dev/os](https://github.com/wolfi-dev/os). This is an unofficial build,
not affiliated with HAProxy Technologies.
