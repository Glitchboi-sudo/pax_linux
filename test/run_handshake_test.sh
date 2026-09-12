#!/usr/bin/env bash
# End-to-end validation of the PAX A_HDSK handshake against the fake terminal.
set -u
cd "$(dirname "$0")/.."
# Locate the pax_adb binary: explicit override, dev tree, or portable layout.
if [ -n "${PAXADB_BIN:-}" ]; then BIN="$PAXADB_BIN"
elif [ -x ./build/pax_adb ]; then BIN=./build/pax_adb
elif [ -x ./pax_adb ]; then BIN=./pax_adb
elif command -v pax_adb >/dev/null 2>&1; then BIN="$(command -v pax_adb)"
else echo "pax_adb binary not found (set PAXADB_BIN)"; exit 2; fi
PORT="${1:-15555}"

pkill -f "pax_adb" 2>/dev/null; sleep 0.3
rm -f /tmp/pax_dev.log /tmp/pax_srv.log

# 1) fake PAX terminal
python3 test/fake_pax_device.py "$PORT" >/tmp/pax_dev.log 2>&1 &
DEVPID=$!
sleep 0.5

# 2) adb server in the foreground (nodaemon) with full tracing
ADB_TRACE=all "$BIN" nodaemon server >/tmp/pax_srv.log 2>&1 &
SRVPID=$!
sleep 0.8

# 3) ask the running server to connect to the fake terminal
"$BIN" connect "127.0.0.1:$PORT" >/tmp/pax_connect.log 2>&1
sleep 1.5
"$BIN" devices >/tmp/pax_devices.log 2>&1
sleep 1.0

# 4) wait for the fake device to finish and grab its verdict
wait "$DEVPID"; DEVRC=$?

# graceful teardown so no detached adb daemon lingers holding our stdout
"$BIN" kill-server >/dev/null 2>&1
kill "$SRVPID" 2>/dev/null
pkill -9 -f "pax_adb" 2>/dev/null
sleep 0.5

echo "================= connect ================="; cat /tmp/pax_connect.log
echo "================= devices ================="; cat /tmp/pax_devices.log
echo "================= fake device ============="; cat /tmp/pax_dev.log
echo "================= server trace (relevant) ================="
grep -iE "HDSK|HANDSHAKE|handshake_response|paxadb|CNXN|online|what is 0x" /tmp/pax_srv.log | head -40
echo "==========================================="
echo "FAKE_DEVICE_RC=$DEVRC"
exit "$DEVRC"
