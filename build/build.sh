#!/usr/bin/env bash
set -e
MOD_NAME="FS25_WinchTow"
TARGET_ZIP="build/${MOD_NAME}.zip"
BUILD_DIR="build/.build_staging"
echo "=== Starting FS25 Mod Packaging Loop ==="
rm -f "$TARGET_ZIP"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
for i in icon.dds scripts/ modDesc.xml handTools/ store/; do
  cp -r "$i" "$BUILD_DIR/$i"
done
( cd "$BUILD_DIR" && zip -rq "../${MOD_NAME}.zip" ./* )
rm -rf "$BUILD_DIR"
echo " SUCCESS: $TARGET_ZIP"
