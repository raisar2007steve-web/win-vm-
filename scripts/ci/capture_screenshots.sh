#!/usr/bin/env bash
# Installs the freshly built app on the simulator, launches it, and captures screenshots.
set -uo pipefail

UDID="${1:-}"
OUT="${2:-ci-artifacts/screenshots}"
BUNDLE_ID="${BUNDLE_ID:-com.raisar2007steve.NotesApp}"

mkdir -p "$OUT"
if [[ -z "$UDID" ]]; then
  echo "No simulator UDID supplied"
  exit 0
fi

APP_PATH=$(find DerivedData/Build/Products -maxdepth 3 -name "NotesApp.app" -type d | head -n 1)
if [[ -z "$APP_PATH" ]]; then
  echo "NotesApp.app not found in DerivedData; skipping screenshot capture"
  exit 0
fi

echo "Booting $UDID"
xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || true
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryLevel 100 --batteryState charged >/dev/null 2>&1 || true

echo "Installing $APP_PATH"
xcrun simctl install "$UDID" "$APP_PATH" || exit 0

echo "Launching $BUNDLE_ID"
xcrun simctl launch "$UDID" "$BUNDLE_ID" -uiScreenshotMode -seedDemoData -uiTesting >/dev/null 2>&1 || true
sleep 6
xcrun simctl io "$UDID" screenshot "$OUT/00-launch.png" >/dev/null 2>&1 || true

# Deep links let the pipeline reach real screens without UI automation.
for target in notes pinned favorites settings; do
  xcrun simctl openurl "$UDID" "notesapp://$target" >/dev/null 2>&1 || true
  sleep 3
  xcrun simctl io "$UDID" screenshot "$OUT/10-$target.png" >/dev/null 2>&1 || true
done

echo "Captured:"
ls -1 "$OUT" 2>/dev/null || true
