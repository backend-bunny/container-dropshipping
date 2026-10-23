#!/usr/bin/env bash
# Regenerate components/<component>/apko.lock.json against today's Wolfi
# index. Local (melange) packages are built first so apko can resolve their
# dependencies, then dropped from the committed lock (see hack/lockfile.py).
# Usage: hack/lock.sh <component>
set -euo pipefail
cd "$(dirname "$0")/.."
source hack/lib.sh

c=${1:?usage: hack/lock.sh <component>}
dir=$(component_dir "$c")

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

build_packages "$c" "$tmp" "$tmp/melange.rsa.pub" notest
fresh_lock "$c" "$tmp/melange.rsa.pub" "$tmp/fresh.lock.json"
python3 hack/lockfile.py strip "$tmp/fresh.lock.json" "$dir/apko.lock.json"
echo "wrote $dir/apko.lock.json"
