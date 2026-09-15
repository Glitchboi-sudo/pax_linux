#!/bin/sh
# Reload udev after the rules file is removed.
set -e

udevadm control --reload-rules 2>/dev/null || true

exit 0
