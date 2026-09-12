#!/usr/bin/env bash
# Verify that `pax_adb systool ...` recovers the device exit code from the
# [SYSTOOL:-N] marker (2021 pax_adb.exe behaviour) and normalises it.
# Shell truncates exit codes to a byte, so a negative ret R shows as 256+R.
set -u
cd "$(dirname "$0")/.."
if   [ -n "${PAXADB_BIN:-}" ]; then BIN="$PAXADB_BIN"
elif [ -x ./build/pax_adb ]; then BIN=./build/pax_adb
elif [ -x ./pax_adb ]; then BIN=./pax_adb
else echo "pax_adb not found"; exit 2; fi

# scenario: "marker-arg | expected-ret"   (empty marker = no marker = success 0)
run() {  # $1=port $2=systool-ret-or-empty $3=expected_ret $4=label
  local port="$1" sr="$2" exp="$3" label="$4"
  pkill -9 -f "pax_adb|fake_pax_full" 2>/dev/null; sleep 0.2
  if [ -n "$sr" ]; then EXTRA="--systool-ret $sr"; else EXTRA=""; fi
  python3 test/fake_pax_full.py "$port" $EXTRA >/tmp/srdev_$port.log 2>&1 &
  sleep 0.4
  "$BIN" connect 127.0.0.1:$port >/dev/null 2>&1
  sleep 0.6
  "$BIN" systool run test >/dev/null 2>&1
  local got=$?
  local expb=$(( (exp % 256 + 256) % 256 ))   # expected as unsigned byte
  local mark="OK"; [ "$got" = "$expb" ] || mark="FAIL"
  printf "  %-22s marker=%-5s -> exit=%-3s (expected %-3s) [%s]\n" "$label" "${sr:-none}" "$got" "$expb" "$mark"
  "$BIN" kill-server >/dev/null 2>&1; pkill -9 -f "pax_adb|fake_pax_full" 2>/dev/null; sleep 0.3
}

echo "===== systool exit-code capture ====="
run 15621 ""    0    "no marker (success)"
run 15622 3     -5   "N=3 -> -5"
run 15623 4     -6   "N=4 -> -6"
run 15624 22    0    "N=22 -> 0"
run 15625 101   0    "N=101 -> 0"
run 15626 305   -305 "N=305 -> preserved"
exit 0
