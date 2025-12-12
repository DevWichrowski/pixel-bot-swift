#!/bin/bash

APP_NAME="PixelBot"
BUILD_DIR=".build/release"
APP_BUNDLE="${APP_NAME}.app"
ICON_SOURCE="AppIcon.png"
ICON_SET="${APP_NAME}.iconset"

echo "🚀 Starting build process for ${APP_NAME}..."

# 1. Build the Swift project
echo "🛠️  Compiling Swift project..."
swift build -c release -Xswiftc -DRELEASE

if [ $? -ne 0 ]; then
    echo "❌ Build failed."
    exit 1
fi

# 2. Create App Bundle Structure
echo "📂 Creating App Bundle structure..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# 3. Handle Icon
if [ -f "${ICON_SOURCE}" ]; then
    echo "🖼️  Generating application icon..."
    mkdir -p "${ICON_SET}"

    sips -z 16 16     "${ICON_SOURCE}" --setProperty format png --out "${ICON_SET}/icon_16x16.png" > /dev/null
    sips -z 32 32     "${ICON_SOURCE}" --setProperty format png --out "${ICON_SET}/icon_16x16@2x.png" > /dev/null
    sips -z 32 32     "${ICON_SOURCE}" --setProperty format png --out "${ICON_SET}/icon_32x32.png" > /dev/null
    sips -z 64 64     "${ICON_SOURCE}" --setProperty format png --out "${ICON_SET}/icon_32x32@2x.png" > /dev/null
    sips -z 128 128   "${ICON_SOURCE}" --setProperty format png --out "${ICON_SET}/icon_128x128.png" > /dev/null
    sips -z 256 256   "${ICON_SOURCE}" --setProperty format png --out "${ICON_SET}/icon_128x128@2x.png" > /dev/null
    sips -z 256 256   "${ICON_SOURCE}" --setProperty format png --out "${ICON_SET}/icon_256x256.png" > /dev/null
    sips -z 512 512   "${ICON_SOURCE}" --setProperty format png --out "${ICON_SET}/icon_256x256@2x.png" > /dev/null
    sips -z 512 512   "${ICON_SOURCE}" --setProperty format png --out "${ICON_SET}/icon_512x512.png" > /dev/null
    sips -z 1024 1024 "${ICON_SOURCE}" --setProperty format png --out "${ICON_SET}/icon_512x512@2x.png" > /dev/null

    iconutil -c icns "${ICON_SET}" -o "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
    rm -rf "${ICON_SET}"
else
    echo "⚠️  ${ICON_SOURCE} not found. Skipping icon generation."
fi

# 4. Copy Files
echo "📋 Copying files..."
cp "Info.plist" "${APP_BUNDLE}/Contents/Info.plist"
cp "${BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

# 5. Codesign with entitlements
echo "🔏 Signing application..."
if [ -f "PixelBot.entitlements" ]; then
    codesign --force --deep --sign - --entitlements "PixelBot.entitlements" "${APP_BUNDLE}"
else
    codesign --force --deep --sign - "${APP_BUNDLE}"
fi

echo "✅ Build complete! ${APP_BUNDLE} is ready."
echo "👉 You can move it to your Applications folder or run it directly."
