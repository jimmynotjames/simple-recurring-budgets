---
name: "App Store: Screenshot Content"
description: Generate culturally-tuned, per-locale demo content for App Store screenshots
category: App Store
tags: [appstore, localization, screenshots]
---

Generate the per-locale **App Store screenshot demo-content** catalog (the budgets
and expenses the app is seeded with when capturing localized screenshots).

Invoke the **`appstore-screenshot-content`** skill (via the Skill tool) and follow
its recipe end to end. If the user passed locale arguments after the command
(e.g. `/appstore:screenshot-content ja de-DE ar-SA`), generate only those
storefronts; otherwise generate every missing locale.

**Definition of done:** `python3 scripts/screenshot_content/check_content.py`
exits 0.

This generates content only. Capturing and uploading screenshots is a separate,
human-gated `fastlane` flow (`fastlane screenshots` → inspect → `fastlane
push_screenshots`); see `fastlane/SETUP.md`.
