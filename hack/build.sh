#!/usr/bin/env bash
# Build one component exactly as CI does:
#   ephemeral melange key -> melange build + test -> apko build from the lock.
# Outputs out/<component>/{image.tar,build.lock.json,sbom-*.spdx.json,sources.{json,md},notices.{json,md},melange.rsa.pub}.
# Usage: hack/build.sh <component>
set -euo pipefail
cd "$(dirname "$0")/.."
source hack/lib.sh

c=${1:?usage: hack/build.sh <component>}
dir=$(component_dir "$c")
out=out/$c
if [[ ! -f $dir/apko.lock.json ]]; then
  echo "error: $dir/apko.lock.json is missing; run: task lock -- $c" >&2
  exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
rm -rf "$out" && mkdir -p "$out"

echo "::group::melange build + test ($c)"
build_packages "$c" "$tmp" "$out/melange.rsa.pub"
echo "::endgroup::"

echo "::group::resolve + check lock ($c)"
fresh_lock "$c" "$out/melange.rsa.pub" "$tmp/fresh.lock.json"
python3 hack/lockfile.py merge \
  "$dir/apko.lock.json" "$tmp/fresh.lock.json" "$dir/apko.yaml" "$out/build.lock.json"
echo "::endgroup::"

echo "::group::apko build ($c)"
keys=()
[[ -s $out/melange.rsa.pub ]] && keys=(--keyring-append "$out/melange.rsa.pub")
mapfile -t annotations < <(version_annotation "$c")
apko build "$dir/apko.yaml" "$REGISTRY/$c:build" "$out/image.tar" \
  --arch "$ARCH" --lockfile "$out/build.lock.json" "${keys[@]}" "${annotations[@]}" \
  --sbom-path "$out"
echo "::endgroup::"

echo "::group::source manifest ($c)"
# Fails if any package's source isn't pinned (see hack/sources.py).
python3 hack/sources.py render "$out/sbom-$ARCH.spdx.json" "$out/image.tar" \
  "$out/sources.json" "$out/sources.md"
echo "::endgroup::"

echo "::group::license notices ($c)"
# License texts + upstream notices for every package (see hack/notices.py).
# Source archives are cached in $CACHE_DIR/notices (CI persists .cache).
python3 hack/notices.py render "$out/sources.json" "$out/image.tar" "$CACHE_DIR/notices" \
  "$out/notices.json" "$out/notices.md"
echo "::endgroup::"

echo "built $out/image.tar"
