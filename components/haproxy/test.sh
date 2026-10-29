#!/usr/bin/env bash
# Smoke test for haproxy: version, config check, no shell, and a live HTTP
# frontend, all with every capability dropped (as under restricted PSS).
# Usage: test.sh IMAGE (with $VERSION = expected HAProxy version)
set -euo pipefail
image=${1:?usage: test.sh IMAGE}
: "${VERSION:?VERSION (expected HAProxy version) is required}"

run=(docker run --rm --cap-drop ALL --security-opt no-new-privileges)

"${run[@]}" "$image" -v | tee /dev/stderr | grep -q "HAProxy version $VERSION"

# Built with the features consumers rely on.
features=$("${run[@]}" "$image" -vv)
for f in +OPENSSL +LUA +PCRE2; do
  grep -q -- "$f" <<<"$features" || { echo "FAIL: haproxy built without $f" >&2; exit 1; }
done

if docker run --rm --entrypoint /bin/sh "$image" -c true 2>/dev/null; then
  echo "FAIL: image has a shell" >&2
  exit 1
fi

cfg=$(mktemp -d)
name=haproxy-test-$$
trap 'docker rm -f "$name" >/dev/null 2>&1 || true; rm -rf "$cfg"' EXIT
cat >"$cfg/haproxy.cfg" <<'EOF'
global
  stats socket /var/lib/haproxy/admin.sock mode 600 level admin
  ssl-default-bind-options ssl-min-ver TLSv1.2

defaults
  mode http
  timeout connect 5s
  timeout client 30s
  timeout server 30s

frontend http
  bind :8080
  http-request return status 200 content-type text/plain string "ok"
EOF
chmod 0755 "$cfg" && chmod 0644 "$cfg/haproxy.cfg"
mount=(--volume "$cfg:/etc/haproxy:ro")

"${run[@]}" "${mount[@]}" "$image" -c -f /etc/haproxy/haproxy.cfg

"${run[@]}" -d --name "$name" "${mount[@]}" --publish 127.0.0.1::8080 "$image" >/dev/null
port=$(docker port "$name" 8080/tcp | head -n1 | cut -d: -f2)
for _ in $(seq 30); do
  if [[ $(curl -fsS "http://127.0.0.1:$port/" 2>/dev/null) == ok ]]; then
    echo "frontend answered"
    exit 0
  fi
  sleep 1
done
docker logs "$name" >&2
echo "FAIL: frontend did not answer" >&2
exit 1
