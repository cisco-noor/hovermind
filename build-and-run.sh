#!/bin/bash
set -e
cd "$(dirname "$0")"

swift build

# Create app bundle if it doesn't exist
if [ ! -d HoverMind.app ]; then
    mkdir -p HoverMind.app/Contents/MacOS
    cp Info.plist HoverMind.app/Contents/Info.plist
fi

cp .build/debug/HoverMind HoverMind.app/Contents/MacOS/HoverMind
SIGN_IDENTITY="${HOVERMIND_SIGN_IDENTITY:--}"
codesign --force --sign "$SIGN_IDENTITY" HoverMind.app
killall HoverMind 2>/dev/null || true
sleep 1
open HoverMind.app
echo "HoverMind launched"
