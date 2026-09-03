#!/bin/bash

set -euo pipefail

PRODUCT_NAME="PixelBot"
APP_NAME="PixelBot Dev"
APP_EXECUTABLE="PixelBot Dev"
BUILD_DIR=".build/release"
APP_BUNDLE="${APP_NAME}.app"
NEW_BUNDLE="${APP_BUNDLE}.building"
ICON_SOURCE="AppIconDev.png"
ICON_SET="${PRODUCT_NAME}.iconset"
SKIN_SOURCE="Resources/TibiaSkin"
EXPECTED_IDENTIFIER="com.pixelbot.tibia.dev"
DEFAULT_SIGNING_IDENTITY="Apple Development: Patryk Wichrowski (7A7BZ23BK3)"
EXPECTED_TEAM_ID="C3W87X2V7H"
TIBIA_SKIN_ASSETS=(
    stoneBackground
    titleBar
    frameOuter
    panelFrame
    fieldFrame
    buttonFrame
    buttonPressedFrame
    tabFrame
    tabSelectedFrame
    slotFrame
    checkboxOff
    checkboxOn
    progressTrack
    progressFillHP
    progressFillMana
    iconHP
    iconMana
    iconStatus
    iconPermissions
    iconRegion
    iconHealing
    iconCombo
    iconHaste
    iconEating
    iconSkinning
)

missing_skin_assets=()
for asset in "${TIBIA_SKIN_ASSETS[@]}"; do
    for suffix in "" "@2x"; do
        asset_path="${SKIN_SOURCE}/${asset}${suffix}.png"
        if [ ! -f "$asset_path" ]; then
            missing_skin_assets+=("$asset_path")
        fi
    done
done

if [ "${#missing_skin_assets[@]}" -ne 0 ]; then
    echo "ERROR: Required Tibia skin assets are missing:"
    printf '  %s\n' "${missing_skin_assets[@]}"
    exit 1
fi

previous_bundle_present=false
previous_identifier=""
previous_team_id=""
previous_requirement=""

cleanup() {
    rm -rf "$ICON_SET" "$NEW_BUNDLE"
}
trap cleanup EXIT

signature_value() {
    local key="$1"
    local bundle="$2"
    codesign -d --verbose=4 "$bundle" 2>&1 \
        | awk -F= -v key="$key" '
            $1 == key && !found {
                print substr($0, index($0, "=") + 1)
                found = 1
            }
        '
}

designated_requirement() {
    local bundle="$1"
    codesign -d -r- "$bundle" 2>&1 | sed -n 's/^designated => //p'
}

if [ -d "$APP_BUNDLE" ]; then
    previous_bundle_present=true
    previous_identifier="$(signature_value Identifier "$APP_BUNDLE" || true)"
    previous_team_id="$(signature_value TeamIdentifier "$APP_BUNDLE" || true)"
    previous_requirement="$(designated_requirement "$APP_BUNDLE" || true)"

    echo "Previous Identifier: ${previous_identifier:-unavailable}"
    echo "Previous Team ID: ${previous_team_id:-unavailable}"
    echo "Previous Designated Requirement: ${previous_requirement:-unavailable}"
fi

available_identities="$(security find-identity -v -p codesigning || true)"

if [ -n "${PIXELBOT_SIGNING_IDENTITY:-}" ]; then
    signing_identity="$PIXELBOT_SIGNING_IDENTITY"
else
    signing_identity="$(printf '%s\n' "$available_identities" \
        | awk -v identity="$DEFAULT_SIGNING_IDENTITY" '
            index($0, "\"" identity "\"") {
                firstQuote = index($0, "\"")
                if (!found && firstQuote > 0) {
                    value = substr($0, firstQuote + 1)
                    sub(/\"$/, "", value)
                    print value
                    found = 1
                }
            }
        ')"
fi

if [ -z "$signing_identity" ]; then
    echo "ERROR: Signing identity '${DEFAULT_SIGNING_IDENTITY}' was not found."
    echo "Install the certificate or set PIXELBOT_SIGNING_IDENTITY explicitly."
    exit 1
fi

if ! printf '%s\n' "$available_identities" | grep -Fq "$signing_identity"; then
    echo "ERROR: Signing identity '${signing_identity}' is not available in the keychain."
    exit 1
fi

echo "Starting release build for ${APP_NAME}."
swift build -c release -Xswiftc -DRELEASE

echo "Creating signed application bundle."
rm -rf "$NEW_BUNDLE"
mkdir -p "$NEW_BUNDLE/Contents/MacOS" "$NEW_BUNDLE/Contents/Resources"

if [ -f "$ICON_SOURCE" ]; then
    echo "Generating application icon."
    rm -rf "$ICON_SET"
    mkdir -p "$ICON_SET"

    sips -z 16 16 "$ICON_SOURCE" --setProperty format png --out "$ICON_SET/icon_16x16.png" >/dev/null
    sips -z 32 32 "$ICON_SOURCE" --setProperty format png --out "$ICON_SET/icon_16x16@2x.png" >/dev/null
    sips -z 32 32 "$ICON_SOURCE" --setProperty format png --out "$ICON_SET/icon_32x32.png" >/dev/null
    sips -z 64 64 "$ICON_SOURCE" --setProperty format png --out "$ICON_SET/icon_32x32@2x.png" >/dev/null
    sips -z 128 128 "$ICON_SOURCE" --setProperty format png --out "$ICON_SET/icon_128x128.png" >/dev/null
    sips -z 256 256 "$ICON_SOURCE" --setProperty format png --out "$ICON_SET/icon_128x128@2x.png" >/dev/null
    sips -z 256 256 "$ICON_SOURCE" --setProperty format png --out "$ICON_SET/icon_256x256.png" >/dev/null
    sips -z 512 512 "$ICON_SOURCE" --setProperty format png --out "$ICON_SET/icon_256x256@2x.png" >/dev/null
    sips -z 512 512 "$ICON_SOURCE" --setProperty format png --out "$ICON_SET/icon_512x512.png" >/dev/null
    sips -z 1024 1024 "$ICON_SOURCE" --setProperty format png --out "$ICON_SET/icon_512x512@2x.png" >/dev/null

    iconutil -c icns "$ICON_SET" -o "$NEW_BUNDLE/Contents/Resources/AppIcon.icns"
else
    echo "WARNING: ${ICON_SOURCE} was not found, skipping icon generation."
fi

cp Info.plist "$NEW_BUNDLE/Contents/Info.plist"
cp "$BUILD_DIR/$PRODUCT_NAME" "$NEW_BUNDLE/Contents/MacOS/$APP_EXECUTABLE"
cp -R "$SKIN_SOURCE" "$NEW_BUNDLE/Contents/Resources/TibiaSkin"

/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $APP_EXECUTABLE" "$NEW_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $EXPECTED_IDENTIFIER" "$NEW_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $APP_NAME" "$NEW_BUNDLE/Contents/Info.plist"
if /usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$NEW_BUNDLE/Contents/Info.plist" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $APP_NAME" "$NEW_BUNDLE/Contents/Info.plist"
else
    /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string $APP_NAME" "$NEW_BUNDLE/Contents/Info.plist"
fi

bundle_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$NEW_BUNDLE/Contents/Info.plist")"
if [ "$bundle_identifier" != "$EXPECTED_IDENTIFIER" ]; then
    echo "ERROR: Unexpected bundle identifier '${bundle_identifier}'."
    exit 1
fi

echo "Signing with identity ${signing_identity}."
codesign --force --sign "$signing_identity" --entitlements PixelBot.entitlements "$NEW_BUNDLE"
codesign --verify --strict --verbose=2 "$NEW_BUNDLE"

identifier="$(signature_value Identifier "$NEW_BUNDLE")"
team_id="$(signature_value TeamIdentifier "$NEW_BUNDLE")"
requirement="$(designated_requirement "$NEW_BUNDLE")"

if [ "$identifier" != "$EXPECTED_IDENTIFIER" ]; then
    echo "ERROR: Signed identifier '${identifier}' does not match '${EXPECTED_IDENTIFIER}'."
    exit 1
fi

if [ "$team_id" != "$EXPECTED_TEAM_ID" ]; then
    echo "ERROR: Signed Team ID '${team_id}' does not match '${EXPECTED_TEAM_ID}'."
    exit 1
fi

if [ -z "$requirement" ]; then
    echo "ERROR: codesign did not produce a Designated Requirement."
    exit 1
fi

if [ "$previous_identifier" = "$EXPECTED_IDENTIFIER" ] && [ "$previous_team_id" = "$EXPECTED_TEAM_ID" ]; then
    if [ "$previous_requirement" != "$requirement" ]; then
        echo "ERROR: Designated Requirement changed from the previous signed build."
        exit 1
    fi
    echo "Designated Requirement matches the previous build."
elif [ "$previous_bundle_present" = true ]; then
    echo "Signature migration detected from the previous bundle."
    echo "The first Apple Development build may require one final Screen Recording and Accessibility grant."
    echo "Run ./build_app.sh again before relying on consecutive-build identity stability."
else
    echo "No previous bundle was available for signature comparison."
    echo "Run ./build_app.sh again before relying on consecutive-build identity stability."
fi

rm -rf "$APP_BUNDLE"
mv "$NEW_BUNDLE" "$APP_BUNDLE"

codesign --verify --strict --verbose=2 "$APP_BUNDLE"
final_identifier="$(signature_value Identifier "$APP_BUNDLE")"
final_team_id="$(signature_value TeamIdentifier "$APP_BUNDLE")"

echo "Identifier: ${final_identifier}"
echo "TeamIdentifier: ${final_team_id}"
codesign -d -r- "$APP_BUNDLE"

echo "Build complete. Launch with: open \"${APP_BUNDLE}\""
