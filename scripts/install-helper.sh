#!/bin/bash
# scripts/install-helper.sh — install + start the privileged helper for development.
# Normally the app does this from its UI; these scripts exist for developers.
set -euo pipefail

cd "$(dirname "$0")/.."

LABEL="com.fancontrol.helper"
BIN="build/FanControl.app/Contents/MacOS/${LABEL}"
PLIST="Sources/FanControlHelper/Resources/${LABEL}.plist"
DST_BIN="/Library/PrivilegedHelperTools/${LABEL}"
DST_PLIST="/Library/LaunchDaemons/${LABEL}.plist"

[[ -f "$BIN" ]] || { echo "missing $BIN — run ./scripts/build.sh first" >&2; exit 1; }

sudo bash -c "
launchctl bootout system '${DST_PLIST}' 2>/dev/null || true
mkdir -p /Library/PrivilegedHelperTools
cp '${BIN}' '${DST_BIN}'
chown root:wheel '${DST_BIN}'
chmod 755 '${DST_BIN}'
cp '${PLIST}' '${DST_PLIST}'
chown root:wheel '${DST_PLIST}'
chmod 644 '${DST_PLIST}'
launchctl bootstrap system '${DST_PLIST}'
launchctl enable 'system/${LABEL}'
"

echo "==> verifying"
launchctl print system/com.fancontrol.helper 2>/dev/null | head -5 || true
echo "==> helper installed"