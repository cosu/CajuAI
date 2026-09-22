#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="CajuAI"
DEST="/Applications/${APP_NAME}.app"
DERIVED="${ROOT}/build/DerivedData"
BUILT="${DERIVED}/Build/Products/Release/${APP_NAME}.app"

cd "${ROOT}"

# Menu bar instances keep files open; replace only after they exit.
killall "${APP_NAME}" 2>/dev/null || true
for _ in {1..20}; do
  pgrep -x "${APP_NAME}" >/dev/null || break
  sleep 0.25
done
killall -9 "${APP_NAME}" 2>/dev/null || true

echo "→ Clean + Release build"
xcodebuild \
  -project "${ROOT}/CajuAI.xcodeproj" \
  -scheme "${APP_NAME}" \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "${DERIVED}" \
  clean build

if [[ ! -d "${BUILT}" ]]; then
  echo "error: expected app at ${BUILT}" >&2
  exit 1
fi

echo "→ Install ${DEST}"
rm -rf "${DEST}"
ditto "${BUILT}" "${DEST}"
open "${DEST}"
echo "✓ Installed and launched ${APP_NAME}"
