#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="SmoothScroll"
SRC_APP="$ROOT_DIR/dist/${APP_NAME}.app"
TARGET_DIR="${TARGET_DIR:-$HOME/Desktop}"
TARGET_APP="$TARGET_DIR/${APP_NAME}.app"

"$ROOT_DIR/scripts/build-app.sh"

mkdir -p "$TARGET_DIR"
rm -rf "$TARGET_APP"
cp -R "$SRC_APP" "$TARGET_APP"

echo "Installed app: $TARGET_APP"
echo "You can now launch it by double-clicking ${APP_NAME}.app"
