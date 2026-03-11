#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${1:?Usage: $0 path/to/Muesli.app}"
FRAMEWORKS_DIR="$APP_DIR/Contents/Frameworks"

mkdir -p "$FRAMEWORKS_DIR"

find_libffi() {
  local candidate
  for candidate in \
    "/opt/homebrew/opt/libffi/lib/libffi.8.dylib" \
    "/usr/local/opt/libffi/lib/libffi.8.dylib" \
    "/Users/runner/miniconda3/lib/libffi.8.dylib" \
    "/Users/pranavhari/miniconda3/lib/libffi.8.dylib"
  do
    if [[ -f "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  find /opt/homebrew /usr/local "$HOME/miniconda3" -name 'libffi.8.dylib' 2>/dev/null | head -n 1
}

LIBFFI_PATH="$(find_libffi || true)"
if [[ -n "${LIBFFI_PATH:-}" && -f "$LIBFFI_PATH" ]]; then
  cp "$LIBFFI_PATH" "$FRAMEWORKS_DIR/libffi.8.dylib"
fi

codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true

echo "Postprocessed $APP_DIR"
