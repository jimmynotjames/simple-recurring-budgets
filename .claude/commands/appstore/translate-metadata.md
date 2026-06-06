---
name: "App Store: Translate Metadata"
description: Transcreate the App Store text listing into all 49 storefront locales
category: App Store
tags: [appstore, localization, metadata]
---

Transcreate the App Store **text metadata** (name, subtitle, keywords, promotional
text, description, release notes) from English into all 49 App Store storefront
locales under `fastlane/metadata/`.

Invoke the **`appstore-translate-metadata`** skill (via the Skill tool) and follow
its recipe end to end.

**Definition of done:** `python3 scripts/translate_metadata/check_metadata.py`
exits 0.

This is the **text-metadata** sibling of `/appstore:screenshot-content` (screenshot
demo data) and `translate-new-strings` (in-app UI strings).
