#!/bin/sh
# Reload udev so the PAX rules take effect right after install/upgrade.
set -e

udevadm control --reload-rules 2>/dev/null || true
udevadm trigger 2>/dev/null || true

echo ":: pax_adb installed to /usr/bin/pax_adb"
echo ":: Unplug/replug your PAX terminal so the new udev rules take effect."
echo ":: If USB access is denied, add your user to the 'plugdev' group"
echo "   (or rely on systemd-logind 'uaccess' when logged in on the local seat)."

exit 0
