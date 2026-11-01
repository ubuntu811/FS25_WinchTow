#!/usr/bin/env bash

# Exit immediately if any command fails
set -e

# Define source archive and destination folder name
MOD_NAME="FS25_WinchTow"
SOURCE_ZIP="build/${MOD_NAME}.zip"
TARGET_DIR_NAME="$HOME/fs25/mods/${MOD_NAME}"

echo "=== Starting FS25 Hot-Reload Deployment Pipeline ==="

# 1. Always rebuild first - real bug found live tonight: the old
# "only build if the zip is missing" version silently deployed a stale
# zip from before a source edit whenever one already happened to exist,
# same class of bug already caught once tonight on the map mods'
# deploy.sh. Unconditional now, matching that fix - build.sh's own cost
# is small, there's no real reason to skip it.
if [ -f "build/build.sh" ]; then
    bash build/build.sh
fi

rm -rf ${TARGET_DIR_NAME}

echo "--> Constructing staging directory at: ${TARGET_DIR_NAME}"
mkdir -p "$TARGET_DIR_NAME"

# 3. Deploy cleanly unzipped development package
echo "--> Unzipping production package directly into development target..."
unzip -q "$SOURCE_ZIP" -d "$TARGET_DIR_NAME"

echo "================================================="
echo " SUCCESS: Mod deployed as a loose unzipped folder!"
echo " Path: ${TARGET_DIR_NAME}"
echo "================================================="

