#!/bin/zsh

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$PROJECT_ROOT/HermitFlow.xcodeproj"
SCHEME="HermitFlow"
CONFIGURATION="${1:-Release}"
DERIVED_DATA_PATH="$PROJECT_ROOT/.DerivedDataPackage"
BUILD_PRODUCTS_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION"
APP_SOURCE_PATH="$BUILD_PRODUCTS_PATH/HermitFlow.app"
DIST_DIR="$PROJECT_ROOT/dist"
APP_DEST_PATH="$DIST_DIR/HermitFlow.app"
PKG_DEST_PATH="$DIST_DIR/HermitFlow.pkg"

if [[ "$CONFIGURATION" != "Release" && "$CONFIGURATION" != "Debug" ]]; then
  echo "Unsupported configuration: $CONFIGURATION"
  echo "Usage: scripts/package.sh [Release|Debug]"
  exit 1
fi

mkdir -p "$DIST_DIR"
rm -rf "$APP_DEST_PATH" "$PKG_DEST_PATH"

echo "Building $SCHEME ($CONFIGURATION)..."
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  build

if [[ ! -d "$APP_SOURCE_PATH" ]]; then
  echo "Build succeeded but app was not found at: $APP_SOURCE_PATH"
  exit 1
fi

echo "Copying app to dist..."
ditto "$APP_SOURCE_PATH" "$APP_DEST_PATH"

echo "Building installer package..."
pkgbuild \
  --install-location /Applications \
  --component "$APP_DEST_PATH" \
  "$PKG_DEST_PATH"

echo
echo "Done."
echo "App: $APP_DEST_PATH"
echo "Pkg: $PKG_DEST_PATH"
