# Contributing to Wren

> Note from maintainer: I generated this file using AI and have not had a chance to test this end-to-end. If you try to reproduce this repo and run into issues, please post an Issue or post a PR to update this file with better instructions. Thanks!

---

> **Branding notice (read before you distribute):** The code is Apache 2.0–licensed, but the Wren name, app icon, and App Store marketing assets are not. See [§ Branding & trademarks](#branding--trademarks) and [TRADEMARK.md](TRADEMARK.md) for what forks must replace before distributing.

---

## Contributing Features and Bug Fixes

I'm not working on this repo regularly, so responses may take some time. That said, if you do not meet the requirements below, your issue or pull request will likely be ignored. Sorry if that feels strict. I'm doing my best to manage my time and ensure this stays a quality product. Remember that you can always fork this repo, add your own desired features, and deploy a debug version on your device for your own use.

Requirements:

- You must prove that you understand this product and have a genuine desire to improve it. Explain your product thinking clearly and concisely. I recommend you hand-write this part and have AI review it. Be prepared to have a conversation.
- For bug fixes, clearly and concisely explain the bug, including detailed reproduction steps. Explain your bug fix and discuss any architectural issue. No "band-aid" fixes will be accepted unless it's a high-severity issue, and it would be a crazy endeavor to refactor appropriately.

Obviously, given that this code is agentically written, I have no issues if you use AI to contribute to this repo. That said, if I sense that you did not put effort into ensuring that your agent was producing quality work, I will likely ignore or reject your pull request or issue.

## Two-tier setup

How much work each goal requires:


| Goal                                     | Gitignored files needed?                                        | Apple account                                        | Quick start                                                    |
| ---------------------------------------- | --------------------------------------------------------------- | ---------------------------------------------------- | -------------------------------------------------------------- |
| **A. Simulator dev**                     | None                                                            | Apple ID in Xcode (only if a signing prompt appears) | `make system` → `make build` → Run on Simulator                |
| **B. Ship / configure for distribution** | `Secrets.local.xcconfig` + `fastlane/.env` + `.p8` outside repo | Apple Developer Program + App Store Connect          | See [§ B](#b--configure-secrets-ship-or-fork-for-distribution) |


```
Tier A — zero secrets               Tier B — ship / full config
────────────────────────            ──────────────────────────────
git clone                           Secrets.local.xcconfig
     ↓                              fastlane/.env + .p8
make system                         Replace branding if distributing
     ↓                                    ↓
make build                          verify_release_secrets.sh (auto)
     ↓                                    ↓
Run on Simulator          ────────▶  fastlane beta / release
(Xcode signing only
 if prompted)
```

To build and run on Simulator only, stop after [§ A](#a--compile-and-run-on-simulator-no-secrets-files).

---



## A — Compile and run on Simulator (no secrets files)

Audience: contributors exploring the code, running unit tests, iterating on UI.

You don't need `config/Secrets.local.xcconfig`, `fastlane/.env`, an App Store Connect API key, or Apple Developer Program enrollment.

### Minimal steps

1. Clone the repo.
2. One-time machine setup:
  ```bash
   make system
  ```
   Installs lefthook hooks, SwiftLint, SwiftFormat, gitleaks; verifies Xcode and Python.
3. Compile:
  ```bash
   make build
  ```
   A Debug → Simulator build; reads committed placeholder values from `config/Secrets.xcconfig`, so no local secrets file is needed.
4. Run on Simulator:
  - From terminal: `make tests` (boots the repo's dedicated Simulator and runs the full test suite), or
  - From Xcode: select an iPhone Simulator → Run (⌘R).

### Simulator concurrency

The test scripts print a line like `simulator-slots: no shared pool on this machine …`. That's expected. The maintainer's machine has a shared pool that caps how many simulators all of their repos run at once (`scripts/simulator-slots/` is that tool's vendored copy). You don't need it, and you shouldn't create its directories. Without the pool, the scripts don't coordinate with anything.

How many simulators the UI test pass uses is up to you:

- Unset (default), the UI pass runs serially on one simulator, the lightest option.
- `UI_WORKERS=2 make ui-tests` (or `3`) runs that many parallel clones and retries a failed test once. Each booted simulator takes about 2–3 GB of RAM.

Details: `AGENTS.md` § "Simulator slots" and the `ios-sims` skill.



### Signing

Simulator builds generally skip code signing and don't enforce entitlements, so `make build` on a fresh clone should succeed without changing the team, even though the project references maintainer team ID `EDMB3Z5KAY`.

Only if a build or run fails on signing or provisioning: open `simple-recurring-budgets.xcodeproj` → `simple-recurring-budgets` app target → Signing & Capabilities → choose your Personal Team (the Apple ID registered in Xcode). Simulator-only dev doesn't require changing the bundle ID or CloudKit container.

### What works with placeholders

- App launches; budgets, expenses, settings, SwiftData (local store; iCloud may show unavailable on Simulator — expected).
- Unit tests and UI tests (`make tests`, `make ui-tests`).
- Analytics: console/no-op (`ConsoleAnalyticsClient`); no Mixpanel SDK, no Mixpanel network traffic.
- Send Feedback opens `noreply@example.com` (placeholder).
- Privacy Policy opens `https://example.com/privacy` (placeholder).

---



## B — Configure secrets, ship, or fork for distribution

Audience: shipping to TestFlight/App Store, using real analytics locally, or publishing a fork as your own app.

Prerequisites to ship: Apple Developer Program enrollment and an App Store Connect app record.

### Step 1 — App secrets (required for Release / Fastlane ship)

```bash
cp config/Secrets.local.xcconfig.template config/Secrets.local.xcconfig
```

Open the file and fill in:


| Key                   | What                                      | Notes                                                                          |
| --------------------- | ----------------------------------------- | ------------------------------------------------------------------------------ |
| `MIXPANEL_DEV_TOKEN`  | Mixpanel project token for Debug builds   | From your Mixpanel project settings                                            |
| `MIXPANEL_PROD_TOKEN` | Mixpanel project token for Release builds | Usually a separate Mixpanel project                                            |
| `FEEDBACK_EMAIL`      | Email address for "Send Feedback"         | Your inbox, not the maintainer's                                               |
| `PRIVACY_POLICY_URL`  | URL of your privacy policy                | Use `https:$(DOUBLE_SLASH)your-site.com/...` syntax — see the template comment |


`config/Secrets.local.xcconfig` is gitignored and must never be committed.

`DOUBLE_SLASH` is required because xcconfig files treat `//` as a line comment; the template shows the format.

### Step 2 — App Store Connect API

```bash
cp fastlane/.env.template fastlane/.env
```

Store your `.p8` key file **outside the repo** (e.g. `~/.appstoreconnect/`) and set the path in `fastlane/.env`. Details in [fastlane/SETUP.md](fastlane/SETUP.md).

### Step 3 — Verify auth

```bash
fastlane verify_auth
```



### Step 4 — Ship

```bash
fastlane beta     # TestFlight
fastlane release  # App Store upload
```

Both lanes run `scripts/verify_release_secrets.sh` before building. If any placeholder sentinel remains, the lane exits immediately with instructions, before archive/sign/upload.

**Escape hatch** (exceptional local Release archives only, not for uploading):

```bash
SKIP_RELEASE_SECRETS_CHECK=1 fastlane beta
```



### What never gets committed


| File                            | Why                                                                                                  |
| ------------------------------- | ---------------------------------------------------------------------------------------------------- |
| `config/Secrets.local.xcconfig` | Contains your real tokens and email                                                                  |
| `fastlane/.env`                 | Contains ASC API key ID and issuer ID                                                                |
| `*.p8`                          | App Store Connect private key. Keep outside the repo entirely. Filepath recorded in `fastlane/.env`. |




### Branding (required if you distribute)

See [§ Branding & trademarks](#branding--trademarks) and [TRADEMARK.md](TRADEMARK.md) for the full policy. Short version: before you upload to TestFlight, submit to the App Store, or distribute a binary to users, you must replace:

- App icon (`simple-recurring-budgets/Resources/AppIcon.icon/`)
- App display name (`CFBundleDisplayName = Wren` in `project.pbxproj`)
- All `fastlane/metadata/`* storefront copy (name, subtitle, keywords, description, promotional text, release notes)
- Screenshot seed content in `simple-recurring-budgetsUITests/ScreenshotSeeds/` (if you generate store screenshots)
- Bundle ID (`com.jimmyho.simple-recurring-budgets` in `project.pbxproj` and `fastlane/Appfile`)
- CloudKit container (`iCloud.com.jimmyho.simple-recurring-budgets` in `.entitlements`)
- Support / marketing URLs in `fastlane/metadata/*/support_url.txt` and `marketing_url.txt`
- Your own `FEEDBACK_EMAIL` and `PRIVACY_POLICY_URL` in `config/Secrets.local.xcconfig`

Tier A (Simulator-only) builds may show Wren branding locally; that is development, not distribution.

---



## Branding & trademarks

The source code is licensed under the Apache License 2.0 (see [LICENSE](LICENSE)), which permits modification and redistribution but explicitly withholds trademark and product-name rights (Apache §6).

The Wren name and these assets are not covered by the code license:


| Asset                               | Location                                                                                                    |
| ----------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| Word mark / app name **Wren**       | `INFOPLIST_KEY_CFBundleDisplayName` in `project.pbxproj`; all in-app branding strings                       |
| App icon                            | `simple-recurring-budgets/Resources/AppIcon.icon/`                                                          |
| App Store metadata (49 storefronts) | `fastlane/metadata/` — incl. name, subtitle, keywords, description, promo text, release notes, support URLs |
| Screenshot seed demo data           | `simple-recurring-budgetsUITests/ScreenshotSeeds/`                                                          |


Forks that only compile and run on a Simulator locally are fine. The trademark rules apply when you distribute: TestFlight, App Store, or any binary delivered to users.

Full policy, permitted uses, and what to replace: [TRADEMARK.md](TRADEMARK.md).

---



## Analytics fork hygiene

If you use your own Mixpanel project for analytics:

1. Set `MIXPANEL_DEV_TOKEN` and `MIXPANEL_PROD_TOKEN` in `config/Secrets.local.xcconfig` to your project tokens.
2. In Mixpanel, filter events by the `bundle_id` super-property to separate your fork's traffic from the official app's. The `bundle_id` super-property is set automatically at init (analytics-spec §11) and matches `CFBundleIdentifier`.

---



## What never belongs in the repo

- `config/Secrets.local.xcconfig` — your real tokens and email (gitignored)
- `fastlane/.env` — ASC API key ID + issuer ID (gitignored)
- `*.p8` — App Store Connect private key (keep outside the repo entirely)
- Any other secret, credential, or personal identifier

Pre-commit hooks (`gitleaks protect --staged`) and CI (`gitleaks detect` over full history) enforce this.

---



## Agent / AI tool reminder

If you are an AI agent working in this codebase:

- **Out-of-repo secrets:** `config/Secrets.local.xcconfig` (gitignored, maintainer-only). Never read or commit it; use `config/Secrets.xcconfig` placeholder defaults for key names only.
- **Ship guard paths:** `scripts/verify_release_secrets.sh` (shell) and `verify_ship_secrets!` (Fastfile helper). Don't bypass without the `SKIP_RELEASE_SECRETS_CHECK=1` escape hatch.
- **Build & test:** follow `AGENTS.md > Build and test` — four-step gate: `make format` → `make lint-fix` → `make build` → `make tests`.
- **Simulators:** a `simulator-slots: no shared pool …` notice is normal outside the maintainer's machine. Run normally; don't create the pool's directories. Choose UI-pass concurrency with `UI_WORKERS`, or ask the developer. Tell the developer once that the pool wasn't found and what concurrency you used. See `AGENTS.md > Simulator slots`.
- **Translations:** adding new user-facing strings requires running the `translate-new-strings` skill. See `AGENTS.md > Cross-cutting concerns`.
- **Branding:** Unless you are deriving your own app with its own branding, do not alter the app icon, Wren name, or store metadata as part of code changes. See `TRADEMARK.md`.

