#!/usr/bin/env bash
# Exercise the PAX client commands (syslog/systool/getappinfo/unlink) against the
# full fake terminal. Arg1=port, arg2=sysver to simulate (default 0).
set -u
cd "$(dirname "$0")/.."
if   [ -n "${PAXADB_BIN:-}" ]; then BIN="$PAXADB_BIN"
elif [ -x ./build/pax_adb ]; then BIN=./build/pax_adb
elif [ -x ./pax_adb ]; then BIN=./pax_adb
else echo "pax_adb not found"; exit 2; fi
PORT="${1:-15555}"; SYSVER="${2:-0}"
LOG=/tmp/pax_open_${PORT}.log; rm -f "$LOG"

pkill -9 -f "pax_adb|fake_pax_full" 2>/dev/null; sleep 0.3
python3 test/fake_pax_full.py "$PORT" --sysver "$SYSVER" --log "$LOG" >/tmp/pax_full_dev_${PORT}.log 2>&1 &
sleep 0.5
"$BIN" connect 127.0.0.1:$PORT >/tmp/pax_c_${PORT}.log 2>&1
sleep 0.8

echo "===== [sysver=$SYSVER] client output ====="
echo "--- syslog ---";      "$BIN" syslog
echo "--- systool status foo ---"; "$BIN" systool status foo
echo "--- getappinfo /tmp/appinfo_${PORT}.bin ---"; "$BIN" getappinfo /tmp/appinfo_${PORT}.bin; echo "pulled: $(cat /tmp/appinfo_${PORT}.bin 2>/dev/null)"
echo "--- unlink /tmp/x ---";       "$BIN" unlink /tmp/x
echo "--- unlink /data/resource/app/thing ---"; "$BIN" unlink /data/resource/app/thing

"$BIN" kill-server >/dev/null 2>&1; pkill -9 -f "pax_adb|fake_pax_full" 2>/dev/null; sleep 0.4

echo "===== services the device saw OPEN ====="
cat "$LOG" 2>/dev/null
echo "===== device log ====="
cat /tmp/pax_full_dev_${PORT}.log 2>/dev/null
exit 0
