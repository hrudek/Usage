#!/usr/bin/env bash
# Installs the simulator build on an iPhone Duo simulator, launches it and
# saves a screenshot of the outer display. simctl cannot unfold the Duo or
# rotate it: the inner display stays dark (powering it on through
# `io screenConfig` draws nothing, powering the outer one off crashes the
# system shell) and its geometry has no landscape mode.
# Usage: duo-screenshots.sh <Usage.app> <output dir>. Never fails the job.
set -uo pipefail
app=$1
out=$2
mkdir -p "$out"
bundle=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist")

# The Duo needs its own runtime build (iOS-27-2-iPhone19-4 on Xcode 27.1),
# so the runtime is the newest one that lists the device type.
read -r devicetype runtime < <(xcrun simctl list -j | python3 -c '
import json, sys
data = json.load(sys.stdin)
duo = [t["identifier"] for t in data["devicetypes"] if "duo" in t["name"].lower()]
def version(r): return tuple(int(p) for p in r["version"].split("."))
runtimes = sorted((r for r in data["runtimes"] if r["platform"] == "iOS" and r["isAvailable"]), key=version, reverse=True)
for t in reversed(duo):
    for r in runtimes:
        if any(s["identifier"] == t for s in r.get("supportedDeviceTypes", [])):
            print(t, r["identifier"]); raise SystemExit
')
[[ -n "${runtime:-}" ]] || { echo '::warning::No iPhone Duo simulator with an installed runtime'; exit 0; }
echo "Device type: $devicetype; runtime: $runtime"
udid=$(xcrun simctl create 'Usage Duo' "$devicetype" "$runtime") || { echo '::warning::Could not create the Duo simulator'; exit 0; }
xcrun simctl boot "$udid"
xcrun simctl bootstatus "$udid" -b >/dev/null
xcrun simctl status_bar "$udid" override --time 9:41 --batteryState charged --batteryLevel 100 \
  --cellularBars 4 --wifiBars 3 >/dev/null 2>&1
xcrun simctl install "$udid" "$app" || { echo '::warning::Could not install Usage'; exit 0; }

# simctl names the outer display LCD and the inner one LCD-1.
outer=$(xcrun simctl io "$udid" enumerate | awk '$1 == "Screen" && $2 == "ID:" { id = $3 } $1 == "Name:" && $2 == "LCD" { print id }')
if [[ -z "$outer" ]]; then
  echo '::warning::No outer display found'
elif xcrun simctl launch "$udid" "$bundle" >/dev/null; then
  sleep 8
  xcrun simctl io "$udid" screenshot --type=png --display="$outer" "$out/outer-closed.png" >/dev/null && echo 'Captured outer-closed'
else
  echo '::warning::Could not launch Usage'
fi
xcrun simctl shutdown "$udid" >/dev/null 2>&1
xcrun simctl delete "$udid" >/dev/null 2>&1
exit 0
