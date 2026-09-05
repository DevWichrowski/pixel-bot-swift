# PixelBot Repository Guide

## Project overview

PixelBot is a native macOS 14+ automation application for Tibia. It is written in Swift 5.9 and built as a Swift Package Manager executable. The app captures the screen, uses Vision OCR to read player status, and sends keyboard or mouse input through CoreGraphics.

Automated gameplay carries account risk. Do not describe the app as safe, compliant, or undetectable. [Tibia Rule 3b](https://www.tibia.com/support/?mobile-app=true&rule=3b&subtopic=tibiarules&theme=false) prohibits using additional software to play automatically and warns that it may lead to punishment.

## Entry points and layout

- `Package.swift`: executable target definition and authoritative source list.
- `App/PixelBotApp.swift`: SwiftUI application entry point, app delegate, permission prompt, and `AppVersion.current`.
- `Bot/TibiaBot.swift`: main `ObservableObject`, feature coordination, persisted settings, and the screen-reading loop.
- `Features/`: healing, combo, haste, eating, and skinning behavior.
- `Services/`: screen capture, Vision OCR, keyboard events, region selection, configuration persistence, and randomness.
- `Models/`: status and persisted configuration models.
- `Views/`: SwiftUI overlay, status, configuration, presets, and shared pixel-art components.
- `Info.plist` and `PixelBot.entitlements`: app-bundle metadata and signing entitlements.
- `build_app.sh`: release build, app-bundle assembly, and ad hoc code signing.
- `test_*.swift`: standalone, print-based Swift test scripts. They are not XCTest targets.

The architecture is MVVM-like with a service layer. `TibiaBot` owns the feature objects, synchronizes settings with `ConfigManager`, captures status through `ScreenCaptureService` and the OCR readers, and schedules feature checks. UI state must remain on the main thread. Hot paths include the recurring bot loop, image capture and cropping, OCR, event-tap callbacks, and input scheduling.

## Runtime permissions and configuration

- Accessibility permission is required for `CGEvent` input and global event taps.
- Screen Recording permission is required for screen capture and OCR.
- The persisted user configuration is `~/Library/Application Support/PixelBot/user_config.json`.
- The app is not sandboxed. Do not add entitlements or broaden permissions without a concrete requirement.
- Do not copy the broad allowlist from `.claude/settings.local.json` into Codex configuration. Codex permissions come from the active user environment.

## Commands

Development build:

```bash
swift build
```

Release build:

```bash
swift build -c release
```

Build and ad hoc sign `PixelBot.app`:

```bash
./build_app.sh
```

The bundle script recreates the repository-root `PixelBot.app`. Run the release executable directly with:

```bash
./.build/release/PixelBot
```

Run each standalone test independently:

```bash
swift test_healer.swift
swift test_combo.swift
swift test_cooldowns.swift
swift test_random_cooldowns.swift
swift test_paladin_combo.swift
swift test_reaction_delay.swift
swift test_spirit_potion.swift
```

There is no configured SwiftLint or XCTest suite. Some older scripts report failures only in printed output, so confirm the final summary says `ALL TESTS PASSED` instead of relying only on the process exit code.

## Swift and macOS conventions

- Match the existing Swift style and keep changes focused. Prefer functional SwiftUI views and focused components.
- Use strict, explicit types at public boundaries. Prefer structs for data and protocols only when they support a real seam.
- Keep AppKit and SwiftUI lifecycle work, `@Published` mutations, and UI updates on the main actor or main queue.
- Treat event taps, timers, dispatch work items, and escaping closures as lifecycle-managed resources. Cancel or remove them when stopping and avoid retain cycles.
- Preserve the existing CoreGraphics coordinate and Retina scaling assumptions unless the task explicitly changes them.
- Reuse Vision requests and avoid allocations, logging, or blocking work in recurring capture and OCR paths.
- Handle Accessibility and Screen Recording denial without crashing or claiming permission was granted.
- Preserve Codable compatibility for `UserConfig` and related models. Existing user configuration must continue to decode unless a migration is part of the task.
- Do not introduce force unwraps unless the invariant is both local and demonstrable.
- New test descriptions must begin with `it("should...")` when using a test framework. For the existing standalone harnesses, begin the description passed to `test` with `should`.
- Each new test should verify one behavior with one assertion or expectation.

## Change workflow

1. Read the real call path and state the intended behavior before editing.
2. For a bug, add or update a focused reproducer when practical, then implement the smallest fix.
3. Touch only files required by the request. Preserve unrelated behavior and backward compatibility.
4. Run the narrowest relevant test scripts, then a development build for production Swift changes. Run all seven scripts for cross-feature or shared timing changes.
5. Review the diff, run `git diff --check`, and report any verification that could not be completed.

Do not treat the simplified classes inside standalone tests as production implementations. When production logic changes, verify that the test model still represents the behavior being tested.

## Versioning and release notes

`AppVersion.current` in `App/PixelBotApp.swift` is the in-app version source and is currently `1.3.0`. `Info.plist` currently declares `CFBundleShortVersionString` as `2.0`, so the repository has an existing version mismatch. Do not silently reconcile or change either value. If a task changes the version, ask which version is authoritative unless the request already says so, then update all requested release metadata consistently.

`build_app.sh` performs a release build with `-DRELEASE`, recreates the bundle, copies `Info.plist` and the executable, and uses ad hoc signing. Treat signing identity, notarization, and distribution changes as separate release work.

## Agent and skill routing

- Use `swift-senior` for Swift architecture, implementation, performance, concurrency, macOS API diagnosis, or code review. Assign explicit file ownership before asking it to edit.
- Use `tibia-expert` for Tibia mechanics, vocabulary, or other domain assumptions. Require fresh sources for facts that may change with game updates.
- Use `anti-detection` only for read-only automation-risk assessment. It must focus on correctness, API safety, reliability, behavioral regularity, unsupported claims, and account risk, not evasion tactics.
- Use `$pixelbot-swift-engineering` for the repository-specific Swift engineering workflow.
- Use `$tibia-domain-expert` for sourced Tibia mechanics research.
- Use `$pixelbot-automation-risk` for a structured, read-only risk review.

When multiple agents are used, divide work by non-overlapping files or read-only responsibilities. Never allow two agents to edit the same file concurrently. Tell editing agents they share the worktree, must preserve other changes, and must not revert work they did not create. The primary agent integrates results and performs final verification.

## Git safety

- Never commit without explicit user approval.
- Never push without explicit confirmation.
- Never delete branches, force push, or rewrite pushed history.
- Never add Codex, OpenAI, Claude, or Anthropic co-author or generation trailers.
- If a commit is explicitly requested, use an English Conventional Commit message in the form `<type>(<scope>): <description>`.
- Preserve `CLAUDE.md` and `.claude/` unless the user explicitly asks to change the Claude configuration.

## Completion criteria

A change is complete when its requested behavior is implemented, relevant tests and builds pass, runtime permission implications are explained, the final diff contains no unrelated edits, and any remaining limitation is stated plainly. Do not claim manual UI, Accessibility, Screen Recording, game behavior, or signed-bundle verification unless it was actually performed.
