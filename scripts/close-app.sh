#!/usr/bin/env bash
set -euo pipefail

osascript -e 'tell application "SmoothScroll" to quit' >/dev/null 2>&1 || true
pkill -x SmoothScroll >/dev/null 2>&1 || true

echo "Requested SmoothScroll quit"
