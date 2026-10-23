#!/usr/bin/env bash
# Smoke test for tofu-ci, mimicking GitLab's Kubernetes executor: no entrypoint,
# scripts fed to `sh`, uid 65532, checkout mounted from a volume owned by
# another uid. Usage: test.sh IMAGE (with $VERSION = expected tofu version)
set -euo pipefail
image=${1:?usage: test.sh IMAGE}
: "${VERSION:?VERSION (expected tofu version) is required}"

entrypoint=$(docker image inspect --format '{{json .Config.Entrypoint}}' "$image")
if [[ $entrypoint != null && $entrypoint != '[]' ]]; then
  echo "FAIL: unexpected entrypoint $entrypoint" >&2
  exit 1
fi

# A checkout owned by this host user (not 65532), group-writable the way
# fsGroup leaves a volume.
repo=$(mktemp -d)
trap 'rm -rf "$repo"' EXIT
git -C "$repo" init -q
git -C "$repo" -c user.name=ci -c user.email=ci@example.invalid \
  commit -q --allow-empty -m init
chmod -R g+rwX,o+rX "$repo"

# The job script is fed on stdin, as GitLab does.
script='
test "$(id -u)" = 65532
test "$(id -g)" = 65532

tofu version
tofu version | head -n1 | grep -qx "OpenTofu v$VERSION"
age --version
curl --version
jq --version
git --version
ssh -V
test -s /etc/ssl/certs/ca-certificates.crt

# Writable HOME.
touch "$HOME/.probe"

# age encrypt/decrypt round trip.
age-keygen -o /tmp/age.key 2>/dev/null
echo hush | age -r "$(age-keygen -y /tmp/age.key)" -o /tmp/secret.age
test "$(age -d -i /tmp/age.key /tmp/secret.age)" = hush

# Checkout owned by another uid: no "dubious ownership" error.
git status --short
git log --oneline -1
touch /builds/repo/written-by-job
'
printf '%s\n' "$script" | docker run --rm -i --entrypoint "" \
  --user 65532:65532 --group-add "$(stat -c %g "$repo")" \
  --volume "$repo:/builds/repo" --workdir /builds/repo \
  --env VERSION="$VERSION" \
  "$image" sh -eux
