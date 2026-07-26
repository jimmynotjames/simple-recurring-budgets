# Security Policy

Wren is a solo hobby project — there's no security team and no SLA, but reports are taken seriously and will get a best-effort response.

## Reporting a vulnerability

Please use GitHub's [private vulnerability reporting](../../security/advisories/new) for this repository (Security tab → "Report a vulnerability") instead of opening a public issue. This opens a private advisory visible only to the maintainer, so any real exploit isn't disclosed before it can be fixed.

## Scope

In scope: security issues in the app itself (e.g. local data handling, iCloud/CloudKit sync) or in this repo's build/release tooling. The app has no app-owned backend or authentication — all sync goes through Apple's CloudKit, gated by the user's iCloud account.

Out of scope: identifiers that are expected to be public for an open-source iOS project (Apple Developer Team ID, bundle identifier, CI configuration) — these aren't secrets and aren't actionable reports on their own.

## Disclosure

Please give a reasonable amount of time to address a confirmed report before any public disclosure.
