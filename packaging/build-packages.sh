#!/usr/bin/env bash
#
# Build cross-distro release artifacts for pax_adb into ./dist:
#   - pax-adb_<ver>-1_amd64.deb          (Debian/Ubuntu/Mint/Pop)
#   - pax-adb-<ver>-1.x86_64.rpm         (Fedora/RHEL/Rocky/Alma/openSUSE)
#   - pax-adb-<ver>-linux-x86_64.tar.gz  (portable, any distro)
#   - pax_adb                            (raw stripped binary)
#
# Run it on / inside a base with an old-enough glibc + OpenSSL 3 so the
# artifacts run everywhere current (Ubuntu 22.04 is the reference base):
#
#   docker run --rm -v "$PWD":/src -w /src ubuntu:22.04 \
#     bash -c 'apt-get update && apt-get install -y build-essential libssl-dev \
#              zlib1g-dev curl ca-certificates file && packaging/build-packages.sh'
#
# The Arch package (.pkg.tar.zst) is built separately with makepkg; see
# packaging/arch/PKGBUILD.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

VERSION="${VERSION:-$(sed -n 's/^pkgver=//p' packaging/arch/PKGBUILD | head -n1)}"
RELEASE="${RELEASE:-$(sed -n 's/^pkgrel=//p' packaging/arch/PKGBUILD | head -n1)}"
[ -n "$VERSION" ] || { echo "!! could not determine VERSION"; exit 1; }
[ -n "$RELEASE" ] || RELEASE=1
export VERSION RELEASE
NFPM_VERSION="${NFPM_VERSION:-2.41.3}"

DIST="$REPO/dist"
rm -rf "$DIST"
mkdir -p "$DIST"

log() { printf '\033[1;36m::\033[0m %s\n' "$*"; }

# 1. Build the binary (stripped for release).
log "Building pax_adb (VERSION=$VERSION)..."
make -C "$REPO" clean >/dev/null
make -C "$REPO" >/dev/null
strip "$REPO/pax_adb" 2>/dev/null || true

# 2. Fetch nfpm if not on PATH.
if ! command -v nfpm >/dev/null 2>&1; then
  log "Fetching nfpm $NFPM_VERSION..."
  tmp="$(mktemp -d)"
  curl -fsSL "https://github.com/goreleaser/nfpm/releases/download/v${NFPM_VERSION}/nfpm_${NFPM_VERSION}_Linux_x86_64.tar.gz" \
    | tar -xz -C "$tmp" nfpm
  export PATH="$tmp:$PATH"
fi

# 3. Build .deb and .rpm from the single nfpm config.
log "Building .deb and .rpm..."
export VERSION
nfpm pkg -f packaging/nfpm.yaml -p deb -t "$DIST/"
nfpm pkg -f packaging/nfpm.yaml -p rpm -t "$DIST/"

# 4. Portable tarball (self-contained, builds nothing on the target).
log "Building portable tarball..."
stage="pax-adb-${VERSION}-linux-x86_64"
tmpdir="$(mktemp -d)"
mkdir -p "$tmpdir/$stage/udev"
install -m755 "$REPO/pax_adb"                              "$tmpdir/$stage/pax_adb"
install -m644 "$REPO/packaging/udev/51-android-pax.rules"  "$tmpdir/$stage/udev/51-android-pax.rules"
install -m755 "$REPO/packaging/portable/install.sh"        "$tmpdir/$stage/install.sh"
install -m644 "$REPO/NOTICE"                               "$tmpdir/$stage/NOTICE"
install -m644 "$REPO/LICENSE"                              "$tmpdir/$stage/LICENSE"
install -m644 "$REPO/README.md"                            "$tmpdir/$stage/README.md"
tar -C "$tmpdir" -czf "$DIST/${stage}.tar.gz" "$stage"
rm -rf "$tmpdir"

# 5. Raw binary.
install -m755 "$REPO/pax_adb" "$DIST/pax_adb"

log "Done. Artifacts in $DIST:"
ls -l "$DIST"
