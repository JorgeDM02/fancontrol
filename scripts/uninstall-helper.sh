#!/bin/bash
# scripts/uninstall-helper.sh — stop and remove the privileged helper.
set -euo pipefail

LABEL="com.fancontrol.helper"
DST_BIN="/Library/PrivilegedHelperTools/${LABEL}"
DST_PLIST="/Library/LaunchDaemons/${LABEL}.plist"

sudo bash -c "
launchctl bootout system '${DST_PLIST}' 2>/dev/null || true
rm -f '${DST_PLIST}'
rm -f '${DST_BIN}'
"
echo "==> helper removed"