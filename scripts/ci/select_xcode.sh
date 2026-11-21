#!/usr/bin/env bash
# Selects the newest non-beta Xcode installed on the macOS runner.
set -euo pipefail

if [[ -n "${XCODE_PATH:-}" ]]; then
  echo "Using XCODE_PATH override: $XCODE_PATH"
  sudo xcode-select -s "$XCODE_PATH"
  sudo xcodebuild -license accept >/dev/null 2>&1 || true
  exit 0
fi

declare -a candidates=()
for app in /Applications/Xcode*.app; do
  [[ -d "$app" ]] || continue
  case "$app" in
    *beta*|*Beta*|*RC*) continue ;;
  esac
  version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app/Contents/Info.plist" 2>/dev/null || echo "0")
  candidates+=("${version}|${app}")
done

if [[ ${#candidates[@]} -eq 0 ]]; then
  echo "No stable Xcode found in /Applications; falling back to xcode-select default."
  xcodebuild -version
  exit 0
fi

best=$(printf '%s\n' "${candidates[@]}" | sort -V | tail -n 1)
path="${best#*|}"
version="${best%%|*}"

echo "Selected Xcode ${version} at ${path}"
sudo xcode-select -s "$path"
sudo xcodebuild -license accept >/dev/null 2>&1 || true
xcodebuild -runFirstLaunch >/dev/null 2>&1 || true
xcodebuild -version
