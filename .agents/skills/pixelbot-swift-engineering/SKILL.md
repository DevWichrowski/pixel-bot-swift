---
name: pixelbot-swift-engineering
description: Implement, diagnose, review, or optimize Swift and macOS code in PixelBot, including SwiftUI, AppKit, CoreGraphics, Vision OCR, permissions, persistence, and recurring-loop performance.
---

# PixelBot Swift Engineering

Use the repository `AGENTS.md` as the project contract. Trace the relevant path from `PixelBotApp` or `TibiaBot` through features and services before changing code.

## Workflow

1. Define the requested behavior and the smallest observable success condition.
2. Inspect production code and the corresponding standalone test model. Do not assume the simplified test copy matches production.
3. For bugs, add a focused reproducer when practical. Keep each new test description prefixed with `should` and each test focused on one assertion.
4. Make surgical changes that preserve persisted `Codable` data, existing hotkeys, mode exclusivity, and unrelated features.
5. Verify the narrow behavior, then run `swift build`. Run all seven root test scripts for changes to shared timing, input, configuration, or orchestration.

## Review priorities

Prioritize state and concurrency correctness, input lifecycle, screen-coordinate handling, Vision request reuse, capture and OCR hot-loop cost, cancellation, permission denial, and configuration compatibility. Treat claims about Accessibility or Screen Recording as unverified until checked in the real signed app. Never silently alter `AppVersion.current`, `Info.plist`, entitlements, signing, or the user's configuration file.

Report changed files, verification performed, and any runtime behavior that still needs manual macOS testing.
