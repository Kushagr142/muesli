#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT/dist-native"
APP_DIR="$DIST_DIR/Muesli.app"
SRC_DIR="$ROOT/native/MuesliNative/Sources/MuesliNativeApp"
BUILD_CONFIG="${1:-release}"
BUILD_DIR="$ROOT/native/MuesliNative/.build-direct/$BUILD_CONFIG"
BIN_PATH="$BUILD_DIR/Muesli"
PYTHON_BIN="$ROOT/.venv/bin/python"

if [[ ! -x "$PYTHON_BIN" ]]; then
  echo "Expected Python runtime at $PYTHON_BIN" >&2
  exit 1
fi

mkdir -p "$DIST_DIR" "$BUILD_DIR"

set +e
swiftc "$SRC_DIR"/*.swift \
  -o "$BIN_PATH" \
  -framework AppKit \
  -framework AVFoundation \
  -framework ApplicationServices \
  -lsqlite3
status=$?
set -e

if [[ $status -ne 0 ]]; then
  cat >&2 <<'EOF'
Native Swift build failed.

If the error mentions:
  - redefinition of module 'SwiftBridging'
  - failed to build module 'AppKit'

then the local Apple Command Line Tools installation is inconsistent and needs to be repaired
before the native shell can be compiled. Reinstall Command Line Tools or install full Xcode,
then rerun this script.
EOF
  exit $status
fi

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/Muesli"
cp "$ROOT/assets/menu_m_template.png" "$APP_DIR/Contents/Resources/menu_m_template.png"
cp "$ROOT/assets/muesli.icns" "$APP_DIR/Contents/Resources/muesli.icns"
cp "$ROOT/bridge/worker.py" "$APP_DIR/Contents/Resources/worker.py"

cat > "$APP_DIR/Contents/Resources/runtime.json" <<JSON
{
  "repo_root": "$ROOT",
  "python_executable": "$PYTHON_BIN"
}
JSON

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>Muesli</string>
  <key>CFBundleDisplayName</key>
  <string>Muesli</string>
  <key>CFBundleIdentifier</key>
  <string>com.muesli.app</string>
  <key>CFBundleVersion</key>
  <string>0.1.0</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleExecutable</key>
  <string>Muesli</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleIconFile</key>
  <string>muesli.icns</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>Muesli records microphone audio for dictation.</string>
  <key>NSInputMonitoringUsageDescription</key>
  <string>Muesli monitors keyboard events to trigger push-to-talk dictation.</string>
</dict>
</plist>
PLIST

chmod +x "$APP_DIR/Contents/MacOS/Muesli"
codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true

echo "Built $APP_DIR"
