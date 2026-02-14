#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="SmoothScroll"
SRC_APP="$ROOT_DIR/dist/${APP_NAME}.app"

resolve_target_app() {
    local explicit_path="${1:-}"
    if [[ -n "$explicit_path" ]]; then
        echo "$explicit_path"
        return
    fi

    if [[ -n "${TARGET_APP:-}" ]]; then
        echo "$TARGET_APP"
        return
    fi

    local candidates=(
        "$HOME/Applications/${APP_NAME}.app"
        "$HOME/Desktop/${APP_NAME}.app"
        "/Applications/${APP_NAME}.app"
    )

    for app_path in "${candidates[@]}"; do
        if [[ -d "$app_path" ]]; then
            echo "$app_path"
            return
        fi
    done

    local target_dir="${TARGET_DIR:-$HOME/Desktop}"
    echo "$target_dir/${APP_NAME}.app"
}

TARGET_APP_PATH="$(resolve_target_app "${1:-}")"

if [[ "$(basename "$TARGET_APP_PATH")" != "${APP_NAME}.app" ]]; then
    echo "Refusing to overwrite unexpected app name: $TARGET_APP_PATH" >&2
    echo "Pass a path ending in ${APP_NAME}.app" >&2
    exit 2
fi

TARGET_DIR_PATH="$(dirname "$TARGET_APP_PATH")"

WAS_RUNNING=0
if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    WAS_RUNNING=1
fi

"$ROOT_DIR/scripts/close-app.sh"
"$ROOT_DIR/scripts/build-app.sh"

mkdir -p "$TARGET_DIR_PATH"
rm -rf "$TARGET_APP_PATH"
cp -R "$SRC_APP" "$TARGET_APP_PATH"
touch "$TARGET_APP_PATH"

OPEN_AFTER_UPDATE="${OPEN_AFTER_UPDATE:-1}"
if [[ "$OPEN_AFTER_UPDATE" == "1" || "$WAS_RUNNING" == "1" ]]; then
    open "$TARGET_APP_PATH"
fi

echo "Updated app: $TARGET_APP_PATH"
