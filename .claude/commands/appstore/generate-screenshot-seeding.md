---
name: "App Store: Generate Screenshot Seeding"
description: Generate culturally-tuned, per-locale demo (seeding) content for App Store screenshots
category: App Store
tags: [appstore, localization, screenshots]
---

Generate the per-locale **App Store screenshot seeding catalog** (the budgets and
expenses the app is seeded with when capturing localized screenshots).

Invoke the **`appstore-generate-screenshot-seeding`** skill (via the Skill tool)
and follow its recipe end to end. If the user passed locale arguments after the
command (e.g. `/appstore:generate-screenshot-seeding ja de-DE ar-SA`), generate
only those storefronts; otherwise generate every missing locale.

**Definition of done:** `python3 scripts/screenshot_content/check_content.py`
exits 0.

This generates seed content only. To capture and upload screenshots, use
`/appstore:generate-push-screenshots`.
