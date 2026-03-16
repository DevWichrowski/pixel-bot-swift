# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PixelBot is a native macOS automation bot for the game Tibia, written in Swift. It uses Apple's Vision.framework for real-time OCR to read HP/Mana values and automates healing, combos, eating, hasting, and skinning.

- **Current version**: 1.1.0 (defined in `App/PixelBotApp.swift` → `AppVersion.current`)
- **Platform**: macOS 14.0+
- **Language**: Swift (swift-tools-version 5.9)
- **Build system**: Swift Package Manager (SPM)
- **Permissions required**: Accessibility (CGEvent keyboard sim) + Screen Recording (ScreenCaptureService)

## Commands

```bash
# Build (development)
swift build

# Build (release)
swift build -c release

# Build .app bundle with codesigning
./build_app.sh

# Run binary directly
./.build/release/PixelBot

# Run a single test file
swift test_healer.swift

# Run all tests
swift test_healer.swift && swift test_combo.swift && swift test_cooldowns.swift && swift test_random_cooldowns.swift && swift test_paladin_combo.swift && swift test_spirit_potion.swift
```

No linting toolchain configured (no SwiftLint).

## Architecture

**Pattern: MVVM + Service Layer**

```
SwiftUI Views (OverlayView / StatusView / ConfigView / PresetsView)
       │ @StateObject
TibiaBot.swift  ← Main orchestrator (ObservableObject, ~25 @Published properties)
       │         Each @Published didSet → feature update + ConfigManager.save()
       ├── Features/
       │     AutoHealer   – HP/Mana healing with dual cooldown tracks (spell vs potion)
       │     AutoCombo    – Attack combo with CFMachPort global hotkey tap
       │     AutoHaste    – Haste spell recasting
       │     AutoEater    – Food timer
       │     AutoSkinner  – Right-click skinning
       └── Services/
             KeyPressService      – CGEvent keyboard simulation (50–100ms hold, persistent source, urgent bypass)
             HPManaReader         – Vision.framework OCR + image hashing (caches unchanged frames)
             AmmoReader           – Ammo tracking for Paladin combo mode
             ScreenCaptureService – Full/region screenshot (shared singleton)
             RegionSelector       – Drag-overlay UI for user to pick HP/Mana screen regions
             ConfigManager        – JSON persistence → ~/Library/Application Support/PixelBot/user_config.json
```

### Key Design Decisions

- **Cooldowns**: Every spell/potion has two separate cooldown tracks. Random offset is `base + random(0..0.1s)` to avoid detectable patterns.
- **OCR pipeline**: `HPManaReader` hashes the captured image before running Vision OCR — skips processing if the frame hasn't changed.
- **Combo hotkey**: Uses `CFMachPort` event tap (global, works outside the app window). Press-and-hold detection starts/stops the combo loop.
- **Config persistence**: `TibiaBot` `@Published` property observers call `ConfigManager.save()` on every change; loaded at startup.
- **Mutually exclusive modes**: Several feature pairs are exclusive (Utito Tempo vs Paladin Combo, Critical-is-Potion vs Spirit Potion). Enabling one auto-disables the other via `didSet` observers in `TibiaBot`.
- **Main loop**: `TibiaBot.runLoop()` runs at 75ms interval — captures screen, OCR reads HP/Mana, then runs all feature checks sequentially. Healing mode selection (standard vs criticalIsPotion vs spiritPotionHeal) branches in this loop.
- **KeyPressService**: Uses a persistent `CGEventSource(stateID: .combinedSessionState)` with `localEventsSuppressionInterval = 0.0` and explicit `flags = []` on events. Key-down, hold (50-100ms), and key-up all execute on the same thread. Healing presses use `urgent: true` to bypass the global cooldown between features.
- **UI**: Single draggable 280×550px overlay window (`OverlayView`) with 3 tabs. Retro pixel-art theme via `PixelArtComponents.swift`.
- **Versioning**: Version string lives in `AppVersion.current` in `App/PixelBotApp.swift`. Displayed in the overlay header.

### Testing Conventions

Tests are standalone Swift scripts at the project root (not XCTest). Each file re-declares simplified versions of production classes (e.g. `MockKeyPressService`, inline `AutoHealer`) and uses print-based assertions. Run with `swift test_<name>.swift`.
