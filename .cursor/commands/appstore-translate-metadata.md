---
name: /appstore-translate-metadata
id: appstore-translate-metadata
category: App Store
description: Transcreate the App Store text listing into all 38 storefront locales
---

Transcreate the App Store **text metadata** (name, subtitle, keywords, promotional
text, description, release notes) from English into all 38 App Store storefront
locales under `fastlane/metadata/`.

Follow the **`appstore-translate-metadata`** skill recipe end to end
(`.cursor/skills/appstore-translate-metadata/SKILL.md`).

On Cursor (no subagent primitive), do the per-storefront transcreation **inline and
serially**: for each `tmp/metadata-prompts/{storefront}.md`, read it, produce the
JSON, and write `tmp/metadata-outputs/{storefront}.json`.

**Definition of done:** `python3 scripts/translate_metadata/check_metadata.py`
exits 0.
