---
name: "App Store: Generate & Push Screenshots"
description: Capture localized App Store screenshots with fastlane and upload them to App Store Connect
category: App Store
tags: [appstore, screenshots, upload]
---

Capture localized App Store screenshots with fastlane and upload them to App Store
Connect.

Invoke the **`appstore-generate-push-screenshots`** skill (via the Skill tool) and
follow its recipe end to end.

**Precondition:** `python3 scripts/screenshot_content/check_content.py` exits 0.
Run `/appstore:generate-screenshot-seeding` first if the catalog is not ready.

**Optional argument — run fully unattended (no prompt):**
- `/appstore:generate-push-screenshots upload-now` → capture, then upload
  immediately (no inspection pause).
- `/appstore:generate-push-screenshots pause` → capture, open the review page, and
  pause for an explicit "proceed" before uploading.
- No argument → the skill asks the pause-vs-upload choice once. (If your message
  already says to upload without stopping, the skill treats that as `upload-now`.)

The skill will:
1. Check the seed catalog gate, then whether capture is already done
2. Resolve the pause-vs-upload choice (from the argument/message, else ask once)
3. Capture via `fastlane screenshots` (~2 h; skipped if already captured),
   self-healing any flaked locales, tracked on 20-minute ticks
4. Open `fastlane/screenshots/screenshots.html` for review
5. Upload via the self-healing retry controller (`upload_with_retry.sh`),
   re-pushing any unconfirmed storefronts, tracked on 20-minute ticks without
   prompting
