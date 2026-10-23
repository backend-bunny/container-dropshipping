#!/usr/bin/env bash
# Push a component built by hack/build.sh (same packages, same build lock) to
# $REGISTRY/<component> under its tags and write the pushed digest to
# out/<component>/digest. With DRY_RUN=1, only print the tags.
# Tags: <version>, <version>-<YYYYMMDD> (when there is an upstream version)
# and sha-<short commit>. Consumers pin by digest.
# Usage: hack/publish.sh <component>
set -euo pipefail
cd "$(dirname "$0")/.."
source hack/lib.sh

c=${1:?usage: hack/publish.sh <component>}
dir=$(component_dir "$c")
out=out/$c
[[ -f $out/build.lock.json ]] || { echo "error: run hack/build.sh $c first" >&2; exit 1; }

version=$(component_version "$c")
commit=$(git rev-parse --short=7 HEAD)
refs=()
if [[ -n $version ]]; then
  refs+=("$REGISTRY/$c:$version" "$REGISTRY/$c:$version-$(date -u +%Y%m%d)")
fi
refs+=("$REGISTRY/$c:sha-$commit")

if [[ -n ${DRY_RUN:-} ]]; then
  printf 'would push %s\n' "${refs[@]}"
  exit 0
fi

keys=()
[[ -s $out/melange.rsa.pub ]] && keys=(--keyring-append "$out/melange.rsa.pub")
# SBOMs come from hack/build.sh and are attached with cosign, not by apko.
apko publish "$dir/apko.yaml" "${refs[@]}" \
  --arch "$ARCH" --lockfile "$out/build.lock.json" "${keys[@]}" \
  --sbom=false --image-refs "$out/image-refs"

# apko writes one "<repo>:<tag>@sha256:..." line per tag; all share a digest.
digest=$(head -n1 "$out/image-refs" | sed 's/.*@//')
echo "$digest" > "$out/digest"
echo "pushed $REGISTRY/$c@$digest"
