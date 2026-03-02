# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PixelBot is a native macOS automation bot for the game Tibia, written in Swift. It uses Apple's Vision.framework for real-time OCR to read HP/Mana values and automates healing, combos, eating, hasting, and skinning.

- **Platform**: macOS 14.0+
- **Language**: Swift 6.1.2
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
swift Tests/test_healer.swift

# Run all tests
swift Tests/test_healer.swift && swift Tests/test_combo.swift && swift Tests/test_cooldowns.swift && swift Tests/test_random_cooldowns.swift && swift Tests/test_paladin_combo.swift && swift Tests/test_spirit_potion.swift
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
             KeyPressService      – CGEvent keyboard simulation (80–120ms hold, shared singleton)
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
- **UI**: Single draggable 280×550px overlay window (`OverlayView`) with 3 tabs. Retro pixel-art theme via `PixelArtComponents.swift`.

### Testing Conventions

Tests are standalone Swift scripts (no XCTest). They use mock classes (e.g. `MockKeyPressService`) and print-based output. There are 79 tests across 6 files in `Tests/`.
