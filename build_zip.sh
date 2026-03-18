#!/bin/bash
# Build SystemTrayTerminal_vX.Y.Z.zip for GitHub Releases
set -e
cd "$(dirname "$0")"

VERSION="$(sed -nE 's/^let kAppVersion = "([^"]+)".*/\1/p' systemtrayterminal.swift | head -n1)"
[ -n "$VERSION" ] || { echo "ERROR: kAppVersion not found in systemtrayterminal.swift"; exit 1; }
ZIP_NAME="SystemTrayTerminal_v${VERSION}.zip"

echo "=== Building ${ZIP_NAME} (v${VERSION}) ==="

# ─── Step 1: Build .app bundle ───
echo "[1/2] Building .app bundle..."
bash build_app.sh

# ─── Step 2: Package zip ───
echo "[2/2] Packaging ${ZIP_NAME}..."
rm -f "$ZIP_NAME"
ditto -ck --sequesterRsrc --keepParent SystemTrayTerminal.app "$ZIP_NAME"

# Add documentation files into the zip
# (ditto creates a clean zip, we use /usr/bin/zip to append extra files)
/usr/bin/zip -j "$ZIP_NAME" install.sh FIRST_READ.txt LICENSE README.md

# Generate SHA256 sidecar for updater integrity verification
SHA256_NAME="${ZIP_NAME}.sha256"
shasum -a 256 "$ZIP_NAME" | awk '{print $1}' > "$SHA256_NAME"

ZIP_SIZE=$(du -sh "$ZIP_NAME" | cut -f1)
echo ""
echo "    ${ZIP_NAME}  →  ${ZIP_SIZE}"
echo "    Contents:"
echo "      SystemTrayTerminal.app"
echo "      install.sh"
echo "      FIRST_READ.txt"
echo "      LICENSE"
echo "      README.md"
echo ""
echo "    SHA256: ${SHA256_NAME}"
echo ""
echo "    Ready for GitHub Release v${VERSION}"
echo "    Upload: gh release create v${VERSION} ${ZIP_NAME} ${SHA256_NAME} --title \"v${VERSION}\""
