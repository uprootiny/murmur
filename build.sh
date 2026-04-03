#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Murmur"
BUNDLE_DIR="build/${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "==> Building ${APP_NAME} (release)..."
swift build -c release

echo "==> Assembling ${APP_NAME}.app bundle..."
rm -rf "${BUNDLE_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

# Copy binary
BINARY=$(swift build -c release --show-bin-path)/${APP_NAME}
cp "${BINARY}" "${MACOS_DIR}/${APP_NAME}"

# Copy Info.plist
cp Sources/Murmur/Info.plist "${CONTENTS_DIR}/Info.plist"

# Create a minimal PkgInfo
echo -n "APPL????" > "${CONTENTS_DIR}/PkgInfo"

echo "==> Done. App bundle at: ${BUNDLE_DIR}"
echo "    To run: open ${BUNDLE_DIR}"
