#!/usr/bin/env bash
# Boot a simulator with a hard deadline. `xcrun simctl bootstatus` can block
# forever when CoreSimulator leaves a device half-booted (observed on the iOS 26
# CI runtime), so never call it without a timeout.
set -euo pipefail

UDID="${1:?usage: boot-simulator.sh <device-udid> [timeout-seconds]}"
TIMEOUT="${2:-180}"

xcrun simctl boot "$UDID" >/dev/null 2>&1 || true

python3 - "$UDID" "$TIMEOUT" <<'PY'
import subprocess
import sys

udid = sys.argv[1]
timeout = int(sys.argv[2])

def run(args, limit):
    try:
        return subprocess.run(args, timeout=limit)
    except subprocess.TimeoutExpired:
        print(f"timed out after {limit}s: {' '.join(args)}", file=sys.stderr)
        return None

def boot_status(limit):
    result = run(["xcrun", "simctl", "bootstatus", udid, "-b"], limit)
    return result is not None and result.returncode == 0

if not boot_status(timeout):
    print(f"bootstatus failed or timed out after {timeout}s; rebooting {udid}",
          file=sys.stderr)
    run(["xcrun", "simctl", "shutdown", udid], 120)
    run(["xcrun", "simctl", "boot", udid], 120)
    if not boot_status(timeout):
        print(f"simulator {udid} did not boot within {timeout}s after reboot",
              file=sys.stderr)
        sys.exit(1)
PY

# bootstatus can return before xcodebuild sees the device as booted.
for _ in $(seq 1 15); do
  if xcrun simctl list devices | grep -q "$UDID.*Booted"; then
    exit 0
  fi
  sleep 2
done
echo "simulator $UDID is not listed as Booted after bootstatus" >&2
exit 1
