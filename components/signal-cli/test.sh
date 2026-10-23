#!/usr/bin/env bash
# Smoke test for signal-cli: version, native libs, HTTP daemon health, no shell.
# Usage: test.sh IMAGE (with $VERSION = expected signal-cli version)
set -euo pipefail
image=${1:?usage: test.sh IMAGE}
: "${VERSION:?VERSION (expected signal-cli version) is required}"

docker run --rm "$image" --version | tee /dev/stderr | grep -q "signal-cli $VERSION"

# Loads libsignal_jni + sqlite natives; fails if a native dep is missing.
docker run --rm "$image" listAccounts

if docker run --rm --entrypoint /bin/sh "$image" -c true 2>/dev/null; then
  echo "FAIL: image has a shell" >&2
  exit 1
fi

name=signal-cli-test-$$
trap 'docker rm -f "$name" >/dev/null 2>&1 || true' EXIT
docker run -d --name "$name" --publish 127.0.0.1::8080 "$image" >/dev/null
port=$(docker port "$name" 8080/tcp | head -n1 | cut -d: -f2)
for _ in $(seq 60); do
  if curl -fsS "http://127.0.0.1:$port/api/v1/check"; then
    echo "daemon healthy"
    exit 0
  fi
  sleep 1
done
docker logs "$name" >&2
echo "FAIL: daemon did not become healthy" >&2
exit 1
