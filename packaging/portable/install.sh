#!/usr/bin/env bash
#
# Portable installer for pax_adb (native Linux adb with the PAX handshake).
# Builds from source in this repository, then installs the binary + udev rules.
#
#   sudo ./packaging/portable/install.sh            build + install to /usr/local/bin + udev
#        ./packaging/portable/install.sh --user     install binary to ~/.local/bin (udev needs sudo)
#        ./packaging/portable/install.sh --uninstall remove installed files
#
# Build deps: a C compiler, OpenSSL and zlib headers.
#   Arch:   pacman -S --needed base-devel openssl zlib
#   Debian: apt install build-essential libssl-dev zlib1g-dev
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PREFIX="${PREFIX:-/usr/local}"
BIN="pax_adb"
UDEV_RULE="51-android-pax.rules"
USER_MODE=0
UNINSTALL=0

for a in "$@"; do
  case "$a" in
    --user) USER_MODE=1 ;;
    --uninstall) UNINSTALL=1 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  esac
done

log() { printf '\033[1;36m::\033[0m %s\n' "$*"; }
err() { printf '\033[1;31m!!\033[0m %s\n' "$*" >&2; }

if [ "$UNINSTALL" = 1 ]; then
  log "Removing pax_adb..."
  rm -f "$PREFIX/bin/$BIN" "$HOME/.local/bin/$BIN" 2>/dev/null || true
  rm -f "/etc/udev/rules.d/$UDEV_RULE" 2>/dev/null || true
  udevadm control --reload-rules 2>/dev/null || true
  log "Done."
  exit 0
fi

log "Building pax_adb from source..."
make -C "$REPO" >/dev/null
log "Build OK: $REPO/$BIN"

if [ "$USER_MODE" = 1 ]; then
  mkdir -p "$HOME/.local/bin"
  install -m755 "$REPO/$BIN" "$HOME/.local/bin/$BIN"
  log "Installed $HOME/.local/bin/$BIN  (ensure ~/.local/bin is on your PATH)"
else
  [ "$(id -u)" = 0 ] || { err "Root needed to install to $PREFIX/bin. Re-run with sudo, or use --user."; exit 1; }
  install -Dm755 "$REPO/$BIN" "$PREFIX/bin/$BIN"
  log "Installed $PREFIX/bin/$BIN"
fi

if [ "$(id -u)" = 0 ]; then
  install -Dm644 "$REPO/packaging/udev/$UDEV_RULE" "/etc/udev/rules.d/$UDEV_RULE"
  udevadm control --reload-rules 2>/dev/null || true
  udevadm trigger 2>/dev/null || true
  log "Installed udev rules and reloaded. Unplug/replug the PAX terminal."
else
  err "Skipped udev rules (need root):"
  err "  sudo install -Dm644 '$REPO/packaging/udev/$UDEV_RULE' /etc/udev/rules.d/$UDEV_RULE"
fi

log "All set. Try:  $BIN devices"
