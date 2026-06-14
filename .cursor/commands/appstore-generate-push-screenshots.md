---
name: /appstore-generate-push-screenshots
id: appstore-generate-push-screenshots
category: App Store
description: Capture localized App Store screenshots with fastlane and upload them to App Store Connect
---

Capture localized App Store screenshots with fastlane and upload them to App Store
Connect.

Follow the **`appstore-generate-push-screenshots`** skill recipe end to end
(`.cursor/skills/appstore-generate-push-screenshots/SKILL.md`).

**Precondition:** `python3 scripts/screenshot_content/check_content.py` exits 0.
Run `/appstore-generate-screenshot-seeding` first if the catalog is not ready.

**Optional argument — run fully unattended (no prompt):**
- `upload-now` → capture, then upload immediately (no inspection pause).
- `pause` → capture, open the review page, and pause for an explicit "proceed"
  before uploading.
- No argument → ask the pause-vs-upload choice once (present as a markdown A/B
  block — Cursor has no AskUserQuestion). If your message already says to upload
  without stopping, treat that as `upload-now`.

The skill will:
1. Check the seed catalog gate, then whether capture is already done
   (`capture_progress.py`)
2. Resolve the pause-vs-upload choice (from the argument/message, else ask once)
3. Capture via `fastlane screenshots` (~2 h; skipped if already captured),
   self-healing any flaked locales, tracked on 20-minute sleep ticks
4. Open `fastlane/screenshots/screenshots.html` in the browser
5. Upload via the self-healing retry controller (`upload_with_retry.sh`),
   re-pushing any unconfirmed storefronts, tracked on 20-minute sleep ticks
   without prompting
