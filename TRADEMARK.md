# Wren Trademark and Branding Policy

> **This document is policy guidance, not legal counsel.** For trademark questions in a commercial or legal context, consult a qualified attorney.

The source code in this repository is licensed under the Apache License 2.0 (see [`LICENSE`](LICENSE)), which permits broad use, modification, and redistribution. However, Apache §6 explicitly withholds trademark rights. This file describes what the code license **does not** cover.

---

## Reserved marks

The following are trademarks and intellectual property of **Jimmy Ho**:

| Mark / Asset | Description | Location in repo |
|---|---|---|
| **Wren** (word mark) | App display name as used in the iOS App Store | `CFBundleDisplayName = Wren` in `project.pbxproj` |
| **Wren app icon** | The stylized icon artwork in all sizes | `simple-recurring-budgets/Resources/AppIcon.icon/` |
| **App Store metadata** | Name, subtitle, keywords, promotional text, description, release notes — all 49 storefront locales | `fastlane/metadata/` |
| **Screenshot seed / demo content** | Locale-specific demo budgets used when capturing App Store screenshots | `simple-recurring-budgetsUITests/ScreenshotSeeds/` |
| **Support URL** | `https://jimmynotjames.github.io/simple-recurring-budgets/` | `fastlane/metadata/*/support_url.txt` |
| **Feedback subject prefix** | "Wren app feedback" in the default email subject | `FeedbackMailto.swift` |

---

## What this policy prohibits (without explicit written permission)

- Distributing an **iOS app or TestFlight build** under the name "Wren" or any confusingly similar name.
- Uploading an **App Store or TestFlight listing** that uses the Wren name, the Wren app icon, or any of the committed App Store metadata text.
- Implying **official affiliation or endorsement** by using "Wren" as your app's product name or as a prominent label in your UI.
- Republishing **captured App Store screenshots** from `fastlane/screenshots/` in a store listing or promotional material for a fork.

---

## What this policy permits (nominative / fair reference)

You **may** use the name "Wren" factually and accurately to describe the origin of your code:

- In your repository's README: *"This is a fork of the [Wren open-source project](https://github.com/jimmynotjames/simple-recurring-budgets)."*
- In documentation or commit messages: *"Based on Wren source code."*
- In source code comments: *"Derived from Wren's `BudgetCalculator`."*

These uses do not employ "Wren" as the **distributed app's name or store title**.

---

## Tier A (Simulator-only development)

**Compiling and running on a local Simulator is permitted and encouraged**, even if Wren branding is visible on screen. Local development is not redistribution.

This policy applies when you **distribute** — defined as delivering a binary (via TestFlight, App Store, ad-hoc, enterprise distribution, or any other means) to users other than yourself.

---

## What to replace before distributing a fork

See [CONTRIBUTING.md § B — Configure secrets, ship, or fork for distribution](CONTRIBUTING.md#b--configure-secrets-ship-or-fork-for-distribution) for the full replacement checklist. Summary:

1. App icon (`simple-recurring-budgets/Resources/AppIcon.icon/`)
2. App display name (`CFBundleDisplayName` in `project.pbxproj`)
3. All `fastlane/metadata/*` storefront copy
4. Screenshot seed content (`simple-recurring-budgetsUITests/ScreenshotSeeds/`)
5. Bundle ID (`com.jimmyho.simple-recurring-budgets` in `project.pbxproj` + `fastlane/Appfile`)
6. CloudKit container (`iCloud.com.jimmyho.simple-recurring-budgets` in `.entitlements`)
7. Support / marketing URLs (`fastlane/metadata/*/support_url.txt`)
8. Your own feedback email and privacy policy URL (`config/Secrets.local.xcconfig`)

---

## Contact

For trademark licensing inquiries, open an issue on this repository or reach out via the support URL above.
