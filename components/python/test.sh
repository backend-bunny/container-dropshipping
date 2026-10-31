#!/usr/bin/env bash
# Smoke test for python: version, stdlib extension modules, no shell, and a
# mounted script run read-only with every capability dropped (as under
# restricted PSS). Usage: test.sh IMAGE (with $VERSION = expected Python version)
set -euo pipefail
image=${1:?usage: test.sh IMAGE}
: "${VERSION:?VERSION (expected Python version) is required}"

run=(docker run --rm --cap-drop ALL --security-opt no-new-privileges --read-only)

"${run[@]}" "$image" --version | tee /dev/stderr | grep -qx "Python $VERSION"

if docker run --rm --entrypoint /bin/sh "$image" -c true 2>/dev/null; then
  echo "FAIL: image has a shell" >&2
  exit 1
fi

app=$(mktemp -d)
trap 'rm -rf "$app"' EXIT
cat >"$app/app.py" <<'EOF'
import os, ssl, sqlite3, ctypes, decimal, lzma, bz2, zlib, uuid, compression.zstd

assert os.getuid() == 65532 and os.getgid() == 65532, (os.getuid(), os.getgid())
assert ssl.create_default_context().cert_store_stats()["x509_ca"] > 0, "no CA certificates"
db = sqlite3.connect(":memory:")
assert db.execute("select 1").fetchone() == (1,)
assert ctypes.CDLL(None).getpid() == os.getpid()
print("ok", ssl.OPENSSL_VERSION)
EOF
chmod 0755 "$app" && chmod 0644 "$app/app.py"

"${run[@]}" --volume "$app:/app:ro" "$image" /app/app.py | tee /dev/stderr | grep -q '^ok '
