---
name: /appstore-generate-screenshot-seeding
id: appstore-generate-screenshot-seeding
category: App Store
description: Generate culturally-tuned, per-locale demo (seeding) content for App Store screenshots
---

Generate the per-locale **App Store screenshot seeding catalog** (the budgets and
expenses the app is seeded with when capturing localized screenshots).

Follow the **`appstore-generate-screenshot-seeding`** skill recipe end to end
(`.cursor/skills/appstore-generate-screenshot-seeding/SKILL.md`). If locale
arguments were passed (e.g. `ja de-DE ar-SA`), generate only those storefronts;
otherwise generate every missing locale.

On Cursor (no subagent primitive), do step 4 **inline and serially**: for each
`tmp/screenshot-content-prompts/{storefront}.md`, read it, produce the JSON, and
write `tmp/screenshot-content-outputs/{storefront}.json`.

**Definition of done:** `python3 scripts/screenshot_content/check_content.py`
exits 0.

This generates seed content only. To capture and upload screenshots, use
`/appstore-generate-push-screenshots`.
