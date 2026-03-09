#!/bin/bash
# quickTERMINAL Installer
set -e

APP="quickTerminal.app"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_PATH="${SCRIPT_DIR}/${APP}"

if [ ! -d "$APP_PATH" ]; then
    echo "Error: ${APP} not found next to this script."
    exit 1
fi

echo "=== quickTERMINAL Installer ==="
echo ""
echo "Removing quarantine flag..."
xattr -cr "$APP_PATH"
echo "Done — app is ready to launch."
echo ""

read -p "Copy to /Applications? (y/n) " choice
if [[ "$choice" =~ ^[Yy]$ ]]; then
    cp -R "$APP_PATH" /Applications/
    echo "Installed to /Applications/"
    echo "Launching..."
    open /Applications/"$APP"
else
    echo "Launching from current directory..."
    open "$APP_PATH"
fi
