# Shared by the hack/*.sh scripts (sourced; cwd is the repo root).

ARCH=x86_64
REGISTRY=${REGISTRY:-ghcr.io/backend-bunny}
MELANGE_RUNNER=${MELANGE_RUNNER:-bubblewrap}
# Download caches reused across builds (CI restores/saves this dir per
# component): language deps at /var/cache/melange inside the build, and the
# Wolfi APKs for melange's build environment.
CACHE_DIR=${CACHE_DIR:-.cache}

# Reproducible timestamps for melange and apko: the commit being built.
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(git log -1 --format=%ct)}
export SOURCE_DATE_EPOCH

component_dir() {
  local dir=components/${1:?component name required}
  if [[ ! -f $dir/apko.yaml ]]; then
    echo "error: no such component: $1 (expected $dir/apko.yaml)" >&2
    return 1
  fi
  echo "$dir"
}

# Upstream version: melange.yaml's package.version or, for Wolfi-only
# components, the locked version of the package named by apko.yaml's
# `# version-package: <name>` comment. Empty if neither exists.
component_version() {
  local dir=components/$1 pkg
  if [[ -f $dir/melange.yaml ]]; then
    awk '/^  version:/ { gsub(/"/, "", $2); print $2; exit }' "$dir/melange.yaml"
    return
  fi
  pkg=$(awk '/^# version-package:/ { print $3; exit }' "$dir/apko.yaml")
  [[ -n $pkg ]] || return 0
  python3 hack/lockfile.py version "$dir/apko.lock.json" "$pkg"
}

# apko arguments adding the upstream version as an OCI annotation (and label),
# for components that have one. Usage: mapfile -t args < <(version_annotation c)
version_annotation() {
  local version
  version=$(component_version "$1")
  [[ -z $version ]] || printf '%s\n' --annotations "org.opencontainers.image.version:$version"
}

# Build (and, unless $4 is "notest", test) component $1's melange package
# into ./packages, signed with a throwaway key. The private key is deleted as
# soon as the APKs are signed; its public half is copied to $3 for apko.
# Key generation happens in a subdir of $2, a temp dir the caller removes.
build_packages() {
  local c=$1 tmp=$2 pub=$3 mode=${4:-test} dir=components/$1
  rm -rf packages
  : > "$pub"
  [[ -f $dir/melange.yaml ]] || return 0

  local key=$tmp/keygen
  mkdir -p "$key"
  (cd "$key" && melange keygen >/dev/null)
  mkdir -p "$CACHE_DIR/melange/$c" "$CACHE_DIR/apk"
  melange build "$dir/melange.yaml" \
    --arch "$ARCH" --runner "$MELANGE_RUNNER" --empty-workspace \
    --cache-dir "$CACHE_DIR/melange/$c" --apk-cache-dir "$CACHE_DIR/apk" \
    --signing-key "$key/melange.rsa" --out-dir packages
  cp "$key/melange.rsa.pub" "$pub"
  rm -rf "$key"

  if [[ $mode != notest ]]; then
    melange test "$dir/melange.yaml" \
      --arch "$ARCH" --runner "$MELANGE_RUNNER" \
      --repository-append ./packages --keyring-append "$pub" \
      --repository-append https://packages.wolfi.dev/os \
      --keyring-append https://packages.wolfi.dev/os/wolfi-signing.rsa.pub
  fi
}

# `apko lock` of component $1 against the current ./packages, written to $3.
fresh_lock() {
  local c=$1 pub=$2 out=$3 keys=()
  [[ -s $pub ]] && keys=(--keyring-append "$pub")
  apko lock "components/$c/apko.yaml" --arch "$ARCH" "${keys[@]}" --output "$out"
}
