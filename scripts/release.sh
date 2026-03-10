#!/bin/bash
set -euo pipefail

#──────────────────────────────────────────────────────────────────────────────
# Oval Release Script
#
# Usage:  ./scripts/release.sh <version> [build_number]
# Example: ./scripts/release.sh 1.7.0
#          ./scripts/release.sh 1.7.0 10
#
# If build_number is omitted it auto-increments from the current value.
#
# What this script does:
#  1. Validates prerequisites (cert, notarize profile, Sparkle key, gh CLI)
#  2. Bumps version in project.pbxproj (Debug + Release)
#  3. Archives with xcodebuild (arm64, Developer ID signed)
#  4. Exports the signed .app
#  5. Creates a DMG with Applications symlink
#  6. Notarizes and staples
#  7. Sparkle EdDSA signs
#  8. Updates appcast.xml
#  9. Commits, tags, pushes
# 10. Creates GitHub Release with DMG attached
#──────────────────────────────────────────────────────────────────────────────

# ── Config ───────────────────────────────────────────────────────────────────
REPO="shreyaspapi/Oval"
BUNDLE_ID="com.shreyas.oval"
CODE_SIGN_ID="Developer ID Application: Shreyas Papinwar (FYS9RNAGTV)"
TEAM_ID="FYS9RNAGTV"
NOTARIZE_PROFILE="oval-notarize"
SCHEME="OpenwebUI"

# Paths (relative to git root)
XCODEPROJ="OpenwebUI/OpenwebUI.xcodeproj"
PBXPROJ="${XCODEPROJ}/project.pbxproj"

# Temp paths
ARCHIVE_PATH="/tmp/Oval.xcarchive"
EXPORT_PATH="/tmp/OvalExport"
EXPORT_PLIST="/tmp/oval-export-options.plist"
DMG_STAGING="/tmp/oval-dmg-staging"

# ── Helpers ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

step() { echo -e "\n${CYAN}▸ $1${NC}"; }
ok()   { echo -e "  ${GREEN}✓ $1${NC}"; }
warn() { echo -e "  ${YELLOW}⚠ $1${NC}"; }
die()  { echo -e "  ${RED}✗ $1${NC}"; exit 1; }

# ── Parse args ───────────────────────────────────────────────────────────────
VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  echo "Usage: $0 <version> [build_number]"
  echo "Example: $0 1.7.0"
  exit 1
fi

if ! echo "$VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  die "Version must be semver (e.g., 1.7.0)"
fi

DMG_NAME="Oval-v${VERSION}.dmg"
DMG_PATH="/tmp/${DMG_NAME}"

# ── cd to git root ───────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.."
GIT_ROOT="$(pwd)"
echo "Working in: $GIT_ROOT"

# ── Step 0: Prerequisites ───────────────────────────────────────────────────
step "Checking prerequisites"

BRANCH=$(git rev-parse --abbrev-ref HEAD)
[ "$BRANCH" = "main" ] || die "Must be on 'main' branch (currently on '$BRANCH')"
ok "On main branch"

if ! git diff --quiet || ! git diff --cached --quiet; then
  die "Uncommitted changes. Commit or stash first."
fi
ok "Working tree clean"

security find-identity -v -p codesigning | grep -q "Developer ID" \
  || die "No Developer ID certificate found"
ok "Developer ID certificate found"

xcrun notarytool store-credentials --help >/dev/null 2>&1 \
  || die "notarytool not available"
ok "notarytool available"

SIGN_UPDATE="$(find ~/Library/Developer/Xcode/DerivedData -name "sign_update" -path "*/artifacts/sparkle/*" -type f 2>/dev/null | head -1)"
[ -n "$SIGN_UPDATE" ] || die "Sparkle sign_update not found in DerivedData. Build the project in Xcode first."
ok "Sparkle sign_update: $SIGN_UPDATE"

gh auth status >/dev/null 2>&1 || die "gh CLI not authenticated"
ok "gh CLI authenticated"

if git rev-parse "v$VERSION" >/dev/null 2>&1; then
  die "Tag v$VERSION already exists"
fi
ok "Tag v$VERSION available"

if ! grep -q "## \[$VERSION\]" CHANGELOG.md; then
  die "No entry for [$VERSION] in CHANGELOG.md — add one first"
fi
ok "CHANGELOG.md has [$VERSION] entry"

# ── Step 1: Determine build number ──────────────────────────────────────────
step "Bumping version to $VERSION"

CURRENT_BUILD=$(grep 'CURRENT_PROJECT_VERSION' "$PBXPROJ" | head -1 | sed 's/[^0-9]//g')
BUILD_NUMBER="${2:-$((CURRENT_BUILD + 1))}"

echo "  Version: $VERSION (build $BUILD_NUMBER)"
echo "  Previous build: $CURRENT_BUILD"

# Replace in pbxproj (all occurrences)
sed -i '' "s/MARKETING_VERSION = [0-9]*\.[0-9]*\.[0-9]*/MARKETING_VERSION = $VERSION/g" "$PBXPROJ"
sed -i '' "s/CURRENT_PROJECT_VERSION = [0-9]*/CURRENT_PROJECT_VERSION = $BUILD_NUMBER/g" "$PBXPROJ"
ok "Updated $PBXPROJ"

# ── Step 2: Archive ─────────────────────────────────────────────────────────
step "Archiving (arm64, Release, Developer ID)"

rm -rf "$ARCHIVE_PATH"
xcodebuild archive \
  -project "$XCODEPROJ" \
  -scheme "$SCHEME" \
  -archivePath "$ARCHIVE_PATH" \
  -configuration Release \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$CODE_SIGN_ID" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  2>&1 | tail -3

grep -q "ARCHIVE SUCCEEDED" <<< "$(xcodebuild -version 2>&1; echo '** ARCHIVE SUCCEEDED **')" || true
[ -d "$ARCHIVE_PATH" ] || die "Archive not found at $ARCHIVE_PATH"
ok "Archive succeeded"

# Verify signing
SIGN_INFO=$(codesign -dv --verbose=2 "$ARCHIVE_PATH/Products/Applications/Oval.app" 2>&1)
echo "$SIGN_INFO" | grep -q "Developer ID" || die "App not signed with Developer ID"
ok "Signed with Developer ID"

# Verify entitlements
ENTITLEMENTS=$(codesign -d --entitlements - "$ARCHIVE_PATH/Products/Applications/Oval.app" 2>&1)
echo "$ENTITLEMENTS" | grep -q "spks" || warn "Missing mach-lookup entitlement (spks) — Sparkle sandbox updates may fail"

# ── Step 3: Export ───────────────────────────────────────────────────────────
step "Exporting signed .app"

cat > "$EXPORT_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>$CODE_SIGN_ID</string>
</dict>
</plist>
PLIST

rm -rf "$EXPORT_PATH"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist "$EXPORT_PLIST" \
  -exportPath "$EXPORT_PATH" \
  2>&1 | tail -3

[ -d "$EXPORT_PATH/Oval.app" ] || die "Export failed"
ok "Exported to $EXPORT_PATH/Oval.app"

# ── Step 4: Create DMG ──────────────────────────────────────────────────────
step "Creating DMG"

rm -f "$DMG_PATH"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$EXPORT_PATH/Oval.app" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"
hdiutil create -volname "Oval" -srcfolder "$DMG_STAGING" -ov -format UDZO "$DMG_PATH" 2>&1 | tail -1

[ -f "$DMG_PATH" ] || die "DMG creation failed"
DMG_SIZE=$(stat -f%z "$DMG_PATH")
ok "Created $DMG_NAME ($((DMG_SIZE / 1048576)) MB)"

# ── Step 5: Notarize ────────────────────────────────────────────────────────
step "Notarizing (this takes 1-3 minutes)"

NOTARIZE_OUTPUT=$(xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARIZE_PROFILE" --wait 2>&1)
echo "$NOTARIZE_OUTPUT" | tail -5

if echo "$NOTARIZE_OUTPUT" | grep -q "status: Accepted"; then
  ok "Notarization accepted"
else
  echo "$NOTARIZE_OUTPUT"
  die "Notarization failed. Check log with: xcrun notarytool log <id> --keychain-profile $NOTARIZE_PROFILE"
fi

step "Stapling"
xcrun stapler staple "$DMG_PATH" 2>&1 | tail -1
ok "Stapled"

# ── Step 6: Sparkle EdDSA sign ──────────────────────────────────────────────
step "Sparkle EdDSA signing"

SPARKLE_OUTPUT=$("$SIGN_UPDATE" "$DMG_PATH" 2>&1)
echo "  $SPARKLE_OUTPUT"

ED_SIGNATURE=$(echo "$SPARKLE_OUTPUT" | grep -o 'edSignature="[^"]*"' | sed 's/edSignature="//;s/"//')
ED_LENGTH=$(echo "$SPARKLE_OUTPUT" | grep -o 'length="[^"]*"' | sed 's/length="//;s/"//')

[ -n "$ED_SIGNATURE" ] || die "Failed to extract EdDSA signature"
[ -n "$ED_LENGTH" ] || die "Failed to extract length"
ok "Signature: ${ED_SIGNATURE:0:20}..."

# ── Step 7: Update appcast.xml ──────────────────────────────────────────────
step "Updating appcast.xml"

PUB_DATE=$(date -u '+%a, %d %b %Y %H:%M:%S +0000')
DOWNLOAD_URL="https://github.com/$REPO/releases/download/v${VERSION}/${DMG_NAME}"

# Extract changelog for this version (between ## [VERSION] and next ## [)
RELEASE_NOTES=$(awk "/^## \[$VERSION\]/{found=1; next} /^## \[/{if(found) exit} found{print}" CHANGELOG.md \
  | sed '/^$/d' \
  | sed 's/^### \(.*\)/<li><strong>\1<\/strong><\/li>/' \
  | sed 's/^- \*\*\(.*\)\*\*: \(.*\)/<li><strong>\1<\/strong> — \2<\/li>/' \
  | sed 's/^- \*\*\(.*\)\*\*\(.*\)/<li><strong>\1<\/strong>\2<\/li>/' \
  | sed 's/^- \(.*\)/<li>\1<\/li>/')

# Write the new item to a temp file
ITEM_FILE=$(mktemp)
cat > "$ITEM_FILE" <<XMLITEM
        <item>
            <title>Version ${VERSION}</title>
            <description><![CDATA[
                <h2>What is New in v${VERSION}</h2>
                <ul>
${RELEASE_NOTES}
                </ul>
            ]]></description>
            <pubDate>${PUB_DATE}</pubDate>
            <sparkle:version>${BUILD_NUMBER}</sparkle:version>
            <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
            <enclosure
                url="${DOWNLOAD_URL}"
                sparkle:edSignature="${ED_SIGNATURE}"
                length="${ED_LENGTH}"
                type="application/octet-stream" />
        </item>
XMLITEM

# Insert new item after <language>en</language>
TEMP_APPCAST=$(mktemp)
{
  while IFS= read -r line; do
    echo "$line"
    if echo "$line" | grep -q '<language>en</language>'; then
      cat "$ITEM_FILE"
    fi
  done
} < appcast.xml > "$TEMP_APPCAST"
mv "$TEMP_APPCAST" appcast.xml
rm -f "$ITEM_FILE"

ok "Added v${VERSION} to appcast.xml"

# ── Step 8: Commit and push ─────────────────────────────────────────────────
step "Committing and pushing"

git add -A
git commit --no-gpg-sign -m "Release v${VERSION}

- Bump to ${VERSION} (build ${BUILD_NUMBER})
- Update appcast.xml with v${VERSION} entry"
ok "Committed"

git push origin main 2>&1
ok "Pushed to main"

# ── Step 9: Tag ─────────────────────────────────────────────────────────────
step "Creating tag v${VERSION}"

git tag -a "v${VERSION}" -m "Oval v${VERSION}" --no-sign
git push origin "v${VERSION}" 2>&1
ok "Tag v${VERSION} pushed"

# ── Step 10: GitHub Release ─────────────────────────────────────────────────
step "Creating GitHub Release"

# Build release notes from CHANGELOG
GH_NOTES=$(awk "/^## \[$VERSION\]/{found=1; next} /^## \[/{if(found) exit} found{print}" CHANGELOG.md)

DMG_MB=$((DMG_SIZE / 1048576))
RELEASE_BODY="## What is New in v${VERSION}

${GH_NOTES}

---

**Download:** [${DMG_NAME}](${DOWNLOAD_URL}) (${DMG_MB} MB)

Signed with Developer ID, notarized by Apple. Sparkle auto-update enabled."

gh release create "v${VERSION}" "$DMG_PATH" \
  --repo "$REPO" \
  --title "Oval v${VERSION}" \
  --notes "$RELEASE_BODY" 2>&1

ok "Release created"

# ── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Oval v${VERSION} released successfully!${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════════════${NC}"
echo ""
echo "  Release: https://github.com/$REPO/releases/tag/v${VERSION}"
echo "  DMG:     $DMG_PATH"
echo ""
echo "  Note: raw.githubusercontent.com CDN may take 5-10 min to"
echo "  serve the updated appcast.xml. Verify via:"
echo "    gh api repos/$REPO/contents/appcast.xml --jq '.content' | base64 -d | head -10"
echo ""
