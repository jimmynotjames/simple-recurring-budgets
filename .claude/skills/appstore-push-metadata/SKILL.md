---
name: appstore-push-metadata
description: "Validate, resolve, review, and upload App Store listing copy to an existing editable version. Copy only: no screenshots, binary, or submission."
---

# Push App Store metadata

Publish the repository metadata as a resolved, reviewable staging tree. Every App Store listing locale has transcreated copy; English remains the fallback for any field a locale does not override.

## Sync with `origin/main`

Before anything else, run `git fetch origin`. On `main`, fast-forward when behind (`git pull --ff-only`); uncommitted edits may stay, and if git refuses, stop and ask. On another branch, don't switch or merge: say how far it is behind `origin/main` and confirm before continuing.

## Prepare and review

1. Run `python3 scripts/translate_metadata/check_metadata.py`. Every storefront must be transcreated and within Apple's limits before anything else happens. If it fails, run the `appstore-translate-metadata` skill and come back; do not hand-edit a storefront file to get past it.
2. Read `fastlane/SETUP.md` and the files under `fastlane/metadata/`. Resolve the intended App Store version from the user's current instruction or active release record. Ask only when absent or conflicting; never infer it from the latest build or make the user repeat an established choice.
3. Run `python3 scripts/appstore_metadata.py validate`. Fix validation failures in source files. An unused optional field has no file; a blank file is rejected, so delete it rather than empty it.
4. Run `python3 scripts/appstore_metadata.py prepare --output tmp/appstore-metadata`.
5. Inspect the generated staging files and command-reported count/path. Spot-check resolved required fields, optional omissions, URLs, locale coverage, and copyright. Treat `tmp/appstore-metadata` as generated review output, not authored source.

Preparation and validation are local and do not authorize an upload.

## Upload

Confirm the exact editable version exists in ASC first; the lane will not create, rename, or select one.

When the user has asked to publish the reviewed metadata, run:

```bash
fastlane ios push_metadata app_version:X.Y.Z
```

Capture the full log under `tmp/`, verify the command targeted the expected editable version, and record the result in the in-flight release record. This lane uploads metadata only: no screenshots, binary, submission, availability, pricing, or phased-release changes.

If the upload partially fails, preserve the staging output and log. Diagnose the exact fields/locales and do not blindly rerun an external mutation.
