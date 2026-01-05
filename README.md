# 🤖 PixelBot Swift

<div align="center">

![Swift](https://img.shields.io/badge/Swift-5.9+-F54A2A?style=for-the-badge&logo=swift&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-14.0+-000000?style=for-the-badge&logo=apple&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-blue?style=for-the-badge)
![Tests](https://img.shields.io/badge/Tests-79%20Passed-brightgreen?style=for-the-badge)

**Native macOS automation bot with blazing-fast OCR powered by Vision.framework**

[Features](#-features) • [Installation](#-installation) • [Usage](#-usage) • [Configuration](#%EF%B8%8F-configuration) • [Architecture](#-architecture)

</div>

---

## ✨ Features

### 🩺 Auto Healing System
| Feature | Description |
|---------|-------------|
| **Normal Heal** | Automatic healing when HP drops below threshold |
| **Critical Heal** | Priority heal at critical HP levels |
| **Auto Mana** | Automatic mana restoration |
| **Potion Mode** | Critical heal shares cooldown with mana (like potions) |
| **Configurable Cooldowns** | Separate spell (0.5s) and potion (0.5s) cooldowns |

### ⚔️ Auto Combo
| Feature | Description |
|---------|-------------|
| **Press & Hold Detection** | Global hotkey to start/stop combo |
| **Random Intervals** | 0.22-0.30s randomized attacks |
| **Auto Loot** | Automatic looting when combo stops |
| **Utito Tempo** | Cast buff before combo starts |
| **Re-cast Utito** | Automatic re-cast every 10 seconds |

### 🛠️ Additional Features
| Feature | Description |
|---------|-------------|
| **Auto Eater** | Timer-based food consumption (Fire/Brown Mushroom) |
| **Auto Haste** | 31-33s interval haste recasting |
| **Auto Skinner** | Right-click triggered skinning |
| **Presets** | Save and load multiple configurations |

---

## 🚀 Performance

| Metric | Python Version | Swift Version |
|--------|----------------|---------------|
| **OCR Speed** | ~100ms (pytesseract) | **~10-20ms** (Vision.framework) |
| **Key Press** | osascript/pyautogui | **CGEvent** (native) |
| **UI Rendering** | Tkinter | **SwiftUI** (native) |
| **Distribution** | Python + venv | **Single .app bundle** |
| **Memory Usage** | ~150MB | **~30MB** |

---

## 📦 Installation

### Option 1: Build from Source

```bash
# Clone the repository
git clone https://github.com/DevWichrowski/pixel-bot-swift.git
cd pixel-bot-swift

# Build with Swift Package Manager
swift build -c release

# Run the app
swift run
```

### Option 2: Build App Bundle

```bash
# Create .app bundle
./build_app.sh

# Move to Applications
mv build/PixelBot.app /Applications/
```

### Option 3: Xcode

1. Open the folder in Xcode
2. Select your signing team
3. Build and Run (`Cmd+R`)

---

## 🎮 Usage

### First Run Setup

1. **Launch the App** - Grant required permissions when prompted
2. **Open CONFIG Tab** - Set up regions and hotkeys
3. **Select HP Region** - Click SELECT and drag over HP bar
4. **Select Mana Region** - Click SELECT and drag over Mana bar
5. **Configure Hotkeys** - Set your heal, mana, and other keys
6. **Start Bot** - Go to STATUS tab and click START

### Interface

```
┌─────────────────────────────────────┐
│  🤖 PIXEL BOT          [STATUS] ▼  │
├─────────────────────────────────────┤
│  ❤️ HP:     450/1000               │
│  💧 MANA:   300/500                │
├─────────────────────────────────────┤
│  ⚡ HEAL     [75%]  ✓              │
│  ⚡ CRIT     [50%]  ✓              │
│  💧 MANA    [60%]  ✓              │
├─────────────────────────────────────┤
│  🍖 EATER   ☐   ⚡ HASTE   ☐      │
│  🔪 SKIN    ☐   ⚔️ COMBO   ☐      │
├─────────────────────────────────────┤
│         [ ▶️ START ]                │
└─────────────────────────────────────┘
```

---

## ⚙️ Configuration

### Config File Location
```
~/Library/Application Support/PixelBot/user_config.json
```

### Cooldown System

| Mode | Spell Cooldown | Potion Cooldown |
|------|----------------|-----------------|
| **Crit is Potion = OFF** | Normal + Critical Heal | Mana only |
| **Crit is Potion = ON** | Normal Heal only | Critical Heal + Mana |

### Hotkeys Reference

| Action | Default | Description |
|--------|---------|-------------|
| Normal Heal | `F1` | Cast healing spell |
| Critical Heal | `F2` | Cast emergency heal |
| Mana Restore | `F4` | Use mana potion |
| Haste | `X` | Cast haste spell |
| Skinner | `[` | Skin creature hotkey |
| Food | `]` | Eat food |
| Combo Start/Stop | `V` | Toggle auto combo |
| Combo Attack | `2` | Attack key for combo |
| Utito Tempo | `F9` | Cast Utito Tempo |
| Auto Loot | `Space` | Loot key after combo |

---

## 🏗️ Architecture

```
PixelBot/
├── App/
│   └── PixelBotApp.swift           # App entry point
├── Bot/
│   └── TibiaBot.swift              # Main bot orchestrator
├── Features/
│   ├── AutoHealer.swift            # HP/Mana healing system
│   ├── AutoCombo.swift             # Combo attack system
│   ├── AutoEater.swift             # Food consumption
│   ├── AutoHaste.swift             # Haste recasting
│   └── AutoSkinner.swift           # Skinning automation
├── Models/
│   ├── UserConfig.swift            # Configuration structures
│   ├── HealConfig.swift            # Heal thresholds
│   └── ConfigManager.swift         # Config persistence
├── Services/
│   ├── ScreenCaptureService.swift  # Screen capture
│   ├── HPManaReader.swift          # OCR reading
│   ├── KeyPressService.swift       # CGEvent key simulation
│   └── RegionSelector.swift        # Region selection overlay
├── Views/
│   ├── OverlayView.swift           # Main overlay window
│   ├── StatusView.swift            # Bot status display
│   ├── ConfigView.swift            # Configuration UI
│   ├── PresetsView.swift           # Presets management
│   └── PixelArtComponents.swift    # Retro UI components
└── Tests/
    ├── test_healer.swift           # Healer tests (19 tests)
    ├── test_combo.swift            # Combo tests (31 tests)
    └── test_cooldowns.swift        # Cooldown tests (29 tests)
```

---

## 🧪 Testing

```bash
# Run all tests
swift test_healer.swift && swift test_combo.swift && swift test_cooldowns.swift

# Individual test files
swift test_healer.swift      # 19 tests - Healing logic
swift test_combo.swift       # 31 tests - Combo system
swift test_cooldowns.swift   # 29 tests - Cooldown system
```

**Total: 79 tests ✅**

---

## 🔐 Required Permissions

| Permission | Purpose |
|------------|---------|
| **Accessibility** | Keyboard simulation using CGEvent |
| **Screen Recording** | Screen capture for OCR |

> ⚠️ These permissions are required for the bot to function. Grant them in **System Preferences → Privacy & Security**.

---

## 🎨 UI Theme

The app features a **retro pixel-art inspired theme** with:
- Monospaced fonts for authentic look
- Custom colored health/mana bars
- Draggable overlay that stays on top
- Dark mode optimized colors

---

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

- Built with ❤️ using Swift and SwiftUI
- OCR powered by Apple's Vision.framework
- Inspired by classic game automation tools

---

<div align="center">

**Made with ☕ and 🎮 by [DevWichrowski](https://github.com/DevWichrowski)**

</div>
