#!/usr/bin/env bash
# Smoke test for crowdsec-web-ui: no shell, uid 65532, native addon, build
# version, and the server healthy on a read-only root (only /app/data written).
# Usage: test.sh IMAGE (with $VERSION = expected crowdsec-web-ui version)
set -euo pipefail
image=${1:?usage: test.sh IMAGE}
: "${VERSION:?VERSION (expected crowdsec-web-ui version) is required}"

if docker run --rm --entrypoint /bin/sh "$image" -c true 2>/dev/null; then
  echo "FAIL: image has a shell" >&2
  exit 1
fi

docker run --rm --entrypoint /usr/bin/node "$image" -e "
  const D = require('/app/node_modules/better-sqlite3');
  console.log('sqlite', new D(':memory:').prepare('select sqlite_version() v').get().v);
  if (process.getuid() !== 65532) throw new Error('uid ' + process.getuid());
  const env = require('fs').readFileSync('/app/build.env', 'utf8');
  if (!env.includes('VITE_VERSION=$VERSION\\n')) throw new Error('build.env: ' + env);
"

name=crowdsec-web-ui-test-$$
trap 'docker rm -f "$name" >/dev/null 2>&1 || true' EXIT
# The LAPI is unreachable: the server must still come up and serve the UI.
docker run -d --name "$name" --read-only --cap-drop ALL \
  --security-opt no-new-privileges \
  --tmpfs /app/data:uid=65532,gid=65532,mode=0750 \
  -e CONFIG_INSTANCE_LAPI_URL=http://127.0.0.1:1 \
  --publish 127.0.0.1::3000 "$image" >/dev/null
port=$(docker port "$name" 3000/tcp | head -n1 | cut -d: -f2)
for _ in $(seq 60); do
  if curl -fsS "http://127.0.0.1:$port/api/health"; then
    echo
    curl -fsS "http://127.0.0.1:$port/" | grep -qi '<html' || {
      echo "FAIL: / did not serve the client" >&2
      exit 1
    }
    echo "server healthy"
    exit 0
  fi
  sleep 1
done
docker logs "$name" >&2
echo "FAIL: server did not become healthy" >&2
exit 1
