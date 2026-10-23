#!/usr/bin/env bash
# Load out/<component>/image.tar into Docker and run components/<component>/test.sh
# against it. The component's upstream version is passed as $VERSION.
# Usage: hack/test.sh <component>
set -euo pipefail
cd "$(dirname "$0")/.."
source hack/lib.sh

c=${1:?usage: hack/test.sh <component>}
dir=$(component_dir "$c")

# apko may suffix the tag (e.g. ":build-amd64"), so use the name docker reports.
image=$(docker load --input "out/$c/image.tar" | sed -n 's/^Loaded image: //p' | head -n1)
if [[ -z $image ]]; then
  echo "FAIL: docker load reported no image for out/$c/image.tar" >&2
  exit 1
fi
echo "testing $image"

# Every image must run as the numeric non-root UID (restricted Pod Security).
user=$(docker image inspect --format '{{.Config.User}}' "$image")
if [[ $user != 65532 && $user != 65532:65532 ]]; then
  echo "FAIL: image user is '$user', want 65532" >&2
  exit 1
fi

if [[ -x $dir/test.sh ]]; then
  VERSION=$(component_version "$c") "$dir/test.sh" "$image"
fi
echo "PASS: $c"
