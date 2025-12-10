# Pixel Bot Swift

Native macOS implementation of the Tibia pixel bot using Swift and SwiftUI.

## Features

All features from the Python version:

- **Auto Heal** - Normal heal at configurable threshold
- **Critical Heal** - Priority heal at lower threshold
- **Auto Mana** - Mana restoration at threshold
- **Critical Is Potion** - Shared cooldown mode
- **Auto Eater** - Timer-based food consumption
- **Auto Haste** - 31-33s interval recasting
- **Auto Skinner** - Right-click triggered skinning

## Advantages over Python

| Feature | Python | Swift |
|---------|--------|-------|
| OCR | pytesseract (~100ms) | Vision.framework (~10-20ms) |
| Key Press | pyautogui/osascript | CGEvent (native) |
| UI | Tkinter | SwiftUI (native macOS) |
| Distribution | Python + venv | Single .app bundle |

## Building

### Option 1: Swift Package Manager

```bash
cd PixelBot
swift build -c release
```

### Option 2: Xcode

1. Open `PixelBot.xcodeproj` in Xcode
2. Select your signing team
3. Build and Run (Cmd+R)

## Required Permissions

The app will request these permissions on first run:

- **Accessibility** - For keyboard simulation (CGEvent)
- **Screen Recording** - For screen capture

## Configuration

Settings are saved to:
```
~/Library/Application Support/PixelBot/user_config.json
```

## Usage

1. Launch the app
2. Go to CONFIG tab
3. Click SELECT to define HP and Mana regions
4. Configure hotkeys as needed
5. Go to STATUS tab
6. Click START

The overlay is draggable and stays on top of all windows.
