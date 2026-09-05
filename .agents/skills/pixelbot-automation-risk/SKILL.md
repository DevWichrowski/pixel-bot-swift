---
name: pixelbot-automation-risk
description: Perform a read-only PixelBot automation-risk assessment covering correctness, macOS API safety, behavioral regularity, account risk, reliability, and unsupported assumptions.
---

# PixelBot Automation Risk

Review only. Do not edit code or external state. Start every assessment with the baseline that automated gameplay violates [Tibia Rule 3b](https://www.tibia.com/support/?mobile-app=true&rule=3b&subtopic=tibiarules&theme=false) and may lead to punishment. Never promise that PixelBot is safe or undetectable.

Inspect the requested files and their callers for:

- correctness, concurrency, cancellation, and resource cleanup;
- Accessibility, Screen Recording, CGEvent, event-tap, and capture API safety;
- polling and timing regularity, action sequencing, cooldown coupling, and long-session behavior;
- permission failures, reliability gaps, unsafe defaults, and unsupported anti-cheat or platform claims;
- risks created by process injection, memory reading, client modification, or anti-cheat tampering.

Do not recommend evasion, behavioral camouflage, deliberate mistakes, invasive bypasses, or ways to conceal automation. Bound recommendations to removing automation, reducing automated scope, adding explicit user control, failing safely, improving ordinary software correctness, or correcting claims.

Return findings ordered by severity. Each finding must include a file and line reference, observed evidence, likely consequence, confidence level, and bounded recommendation. Separate repository evidence from inference. End with verification gaps and avoid an all-clear conclusion when no finding proves safety.
