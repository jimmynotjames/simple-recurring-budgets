---
name: /appstore-prepare-for-release
id: appstore-prepare-for-release
category: App Store
description: Drive an App Store release collaboratively via the master checklist and a per-release snapshot
---

Drive (or resume) an **App Store release** of Wren, working through
`docs/app-store-release-checklist.md` collaboratively with the user.

Follow the **`appstore-prepare-for-release`** skill recipe
(`.cursor/skills/appstore-prepare-for-release/SKILL.md`): locate or create the release
snapshot in `releases/vX.Y.Z.md`, resume at the first unchecked item, and
update the snapshot after every item.

On Cursor, sibling steps that reference Claude slash commands map to the
mirrored skills under `.cursor/skills/` (e.g. `appstore-translate-metadata`,
`appstore-generate-push-screenshots`, `translate-new-strings`).

Major checkpoints: **submit for review** (manual ASC click, P5.2) and the
**7-day post-release monitoring window** (Phase 7), after which the
`RELEASES.md` entry is filled in and the snapshot closed.

**Definition of done for a session:** the snapshot on disk reflects everything
that happened this session, and the user knows when/why to re-invoke.
