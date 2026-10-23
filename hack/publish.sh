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

# The tags point at an image index. apko's --image-refs lists the per-arch
# manifests inside it, so resolve the digest the tag actually points to:
# that is what consumers pin and what cosign must sign.
digest=$(docker buildx imagetools inspect "${refs[0]}" --format '{{json .Manifest}}' \
  | python3 -c 'import json, sys; print(json.load(sys.stdin)["digest"])')
if [[ $digest != sha256:* ]]; then
  echo "error: could not resolve the index digest of ${refs[0]}" >&2
  exit 1
fi
echo "$digest" > "$out/digest"
echo "pushed $REGISTRY/$c@$digest"
