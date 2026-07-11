---
name: "App Store: Push Release Build"
description: Bump the version and upload the App Store release-candidate build via fastlane (no review submission)
category: App Store
tags: [appstore, release, fastlane]
---

Build and upload the **App Store release-candidate build**: confirm the
release checklist (`/appstore:prepare-for-release`) has been worked through,
prompt for the new version number, bump `MARKETING_VERSION` on a release
branch, run `fastlane ios beta` so the candidate lands in TestFlight
(**does not submit for review**), then PR → CI → squash-merge.

One binary serves both purposes: the build the user then tests via TestFlight
is the exact build attached to the App Store version in ASC.

Invoke the **`appstore-push-release-build`** skill (via the Skill tool) and
follow its recipe end to end.

**Definition of done:** release-candidate build N (vX.Y.Z) uploaded and
processing in App Store Connect, PR merged to `main`, and the user told to
manually test build N via TestFlight before attaching it and clicking Submit
for Review in ASC.

This is the App Store sibling of `/appstore:push-testflight-build` (same
`fastlane ios beta` lane, plus the checklist confirmation and version bump),
and the release-candidate build step (P4.1) of the
`/appstore:prepare-for-release` checklist.
