# Simple Recurring Budgets App PRD


| Field              | Value      |
| ------------------ | ---------- |
| **Version**        | 1.2        |
| **Last Updated**   | 2026-05-31 |
| **Author / Owner** | Jimmy Ho   |


> This document is the governing source of truth for the app. It defines the north star, guiding principles, and global constraints that every feature, design decision, and technical choice must align with. For more details about specific features, see [product-features-planning.md](product-features-planning.md). For more information UX guidelines, see [ux-design-brief.md](ux-design-brief.md).

## Release Status

This app has not been released to production and is not in the App Store. It is currently "greenfield."

## App Store Details

App Name (<=30 chars): *Wren – Daily Expense Tracker* 
App Icon Name: *Wren*
Subtitle (<=30 chars): *Easy, fast budgeting on the go*

Factors to consider:
- App Icon Name should fit under app icon okay, preferably in all languages. 
- Future Siri integration prefers a name that is more easily recognized by voice recognition. For example, perhaps avoid one-syllable names. That said, info.plist allows alternate names to be recognized by Siri, but increases education overhead for user slightly.
- Resonates with customers. See User Stories section and the [ux-design-brief.md](ux-design-brief.md).
- Try to stand out amongst many, many budgeting, expense tracking apps. 
- Try to indicate quickly how this app is different from other budgeting apps. For example, this app is NOT a business travel expense tracker, NOT a master budgeting tool for a user's total personal finance, does NOT integrate with banking, etc. etc.
- Be able to translate well into foreign languages, though this is less of an issue if we keep things culturally aware during the translations process.

---

## 1. Vision and North Star

An app that gives users more discipline in their personal spending when it comes to regular, repeating expenses. Examples include daily food expenses or weekly groceries and so on.

---

## 2. Problem Statement

### 2.1 Background / Context

A gazillion apps exist in the Apple App Store to budget and track expenses for personal use, covering a lot of use cases. Examples include expense tracking for business travelers, personal budgeting tools, apps that help a person analyze their finances, tools that connect with banks and credit cards, and on and on. 

### 2.2 Pain Points

Current budgeting apps in the marketplace are heavyweight for both initial setup and ongoing use. Personal finance is very, well, personal, and an app's model of organizing finances is unlikely to match the user's mental model. Apps that try to take over all of a user's personal finances are especially suspect.

More simple apps may exist to do more simple tracking but they tend to not be visually elegant. They add distracting visual elements or color palettes. 

Existing apps may add graphs and charts that seem nominally useful, but I question how much utility users actually receive from them. 

Many apps require more UI steps to input data than users are willing to tolerate for routine logging.

Many apps make it hard for users to answer the question: Should I buy this thing now? That is, real-time decision-making takes time for them to look up where they're at with their finances. Furthermore, integration with banks for credit and debit card balances is convenient, but there's usually a 2-day delay to post transactions. Even checking pending transactions is suspect because in the US, they often don't include tipping in the pending amount. This makes it hard for users to exercise discipline for categories of spending that are regularly recurring, especially on a daily basis.

### 2.3 Target Users

Tech-savvy people who want to control their expenses better. They may or may not have their own personal finance frameworks and apps to handle higher-level budgeting. 

Whatever their mental model, we assume that they can distill their spending limits for recurring expenses down to $30 per day, or $100 per week, and so on.

These users want to know in-the-moment whether they can afford a recurring expense category item, like food, groceries, and so on.

---

## 3. Guiding Principles

1. UX Simplicity - We make no assumptions about the user's mental model of their higher-level finances.
2. Ease of Use - Day-to-day interactions should feel efficient and easeful, requiring minimal user input (e.g. logging an expense should take as few taps as reasonably possible).
3. Clarity - Users clearly understand where they stand in real time with respect to their recurring budgets so they can confidently decide how to spend their budgets.
4. Delight - The above principles take priority, but when possible, the app should be fun and cute.

---

## 4. Goals and Success Metrics

### 4.1 Business Goals

None

### 4.2 User Goals

- Minimal effort by users to add expenses.
- Minimal effort by users to see what their budget status is, to help them decide on purchases.

### 4.3 Key Performance Indicators (KPIs)

- Minimal bugs in production.
- Minimal complaints in App Store reviews.

---

## 5. User Personas

### Persona 1 — Juliette

Juliette, woman, 26 years old, is living a typical, frantic New York life. She has a stable white collar job that easily pays the rent for her shoebox of an apartment but her expenses are a mess. She has no financial tracking system whatsoever. Wrangling her finances is too overwhelming but she thinks she can at least break down the problem into daily and weekly spending. She wants to spend no more than $25/day on food and groceries, $7/day on coffee, and no more than $100/week on beauty supplies and cute clothes. She won't stick with any app that feels like a chore to open and log into.

### Persona 2 — Colin

Colin, man, 34 years old, is working to support his wife and two kids as a construction foreman in Kansas City. He has a good grasp on his high-level finances, which are on spreadsheets that he and his wife put together. However, day-to-day financial decisions are still a pain point. It's annoying to consult a big spreadsheet on his phone with monthly numbers just to understand if he should splurge on ice cream sundaes for the kids. He can break down his spending allocations into smaller chunks, divided by category and temporal rhythm (daily, weekly), but he doesn't have an easy way to track it. Whatever tool he uses has to be quick to log into on the go — he's not going to tap through a bunch of screens while wrangling the kids.

### Persona 3 — Paige

Paige, woman, 42, is a project manager living in Fort Collins, CO, with her husband and daughter. She is very organized and knows her finances well. She wants to carve out a budget for herself for those little luxuries and fun expenses, but wants to keep it disciplined. She thinks that setting a daily or weekly spending amount would work, but needs an easy way to track the budget. Current apps are too heavyweight. She enjoys working with tools that are not only useful but fun and cute to use. Finally, she wants logging a purchase to take just seconds so tracking stays a habit, not a burden.

---

## 6. Global Constraints

Constraints that apply universally across every feature and release.

### 6.1 Platform and Compatibility

- iOS, iPadOS, macOS. Primary focus on iOS.
- Only target latest major operating system version and latest general release Swift version.

### 6.2 Performance

- None

### 6.3 Security and Privacy

- Protect user's privacy with the usual Apple tools, such as native encryption of application data files, DBs, etc.

### 6.4 Accessibility

We will support

- Dynamic Type
- VoiceOver

See §6.8 for the ongoing-concern rule that applies to every code change.

### 6.5 Localization / Internationalization

- Support all global users with access to Apple apps. 
- Support for all global languages
- Includes supporting all currency symbols, but not currency exchange conversions.

See §6.8 for the ongoing-concern rule that applies to every code change.

### 6.8 Cross-cutting ongoing concerns

The following concerns are **not** features that complete — they are durable requirements that every feature and code change must uphold. Failing to address them in the same change that introduces new user-facing UI is a defect, not a follow-up. These concerns apply regardless of how a change is described (new feature, bug fix, refactor); whenever UI is added or modified, each concern below must be reviewed and updated as applicable.

The one-time **initial build-out** of each concern below has shipped and is recorded as a completed feature in [`docs/product-features-planning.md`](product-features-planning.md) (Accessibility and Dark Mode under T-3 — F-3.01, F-3.02, F-3.05; Localization under F-3.03; Analytics under F-8.02 — all marked Implemented). The durable, per-change maintenance requirements are canonical **here**; those feature entries cover only the historical build-out and point back to this section.

#### 6.8.1 Accessibility

**Dynamic Type.** Every new UI surface must:

- Use semantic system text styles (`Text`, `Label`, etc. with `.title`, `.body`, `.caption`, …); no fixed point sizes.
- Use `@ScaledMetric` for any custom spacing or dimension that should scale with type size.
- Avoid fixed frame heights that clip text at `.xxxLarge` Dynamic Type or above.
- Remain usable and readable at `.xxxLarge` accessibility size (sample-tested at least once per major new screen).

**VoiceOver.** Every new UI surface must:

- Give all interactive and informational elements meaningful `.accessibilityLabel` values.
- Collapse custom composite views (e.g. carry-over chip, currency picker rows, section headers) to a single VoiceOver element via `.accessibilityElement(children: .ignore)` paired with a composed `.accessibilityLabel(...)`.
- Mark section headings on `List` / form screens with `.accessibilityAddTraits(.isHeader)` so the VoiceOver headings rotor surfaces them.
- Give destructive controls (Reset Budget, Reset Carry-Over, Delete Budget, Delete Expense, swipe-to-delete) an `.accessibilityHint(...)` describing the irreversible consequence.
- Pair every `swipeActions` with an `.accessibilityAction(named:)` mirroring the gesture so VoiceOver users can invoke it via the rotor.

Live VoiceOver walkthrough and pseudo-loc smoke procedures are documented in Appendices B and C of [`docs/audits/localization+voiceover-audit-2026-04-30.md`](audits/localization+voiceover-audit-2026-04-30.md) and are delegated to the human verifier on real hardware.

#### 6.8.2 Dark Mode

Every new UI surface must:

- Use named color assets from `Resources/Assets.xcassets` with separate light/dark appearances for all custom colors (see `docs/tech-design-doc.md` §5.5 for the color asset table and `appBackground()` modifier pattern).
- Use semantic system colors throughout; no hard-coded color literals.
- Permitted system-palette exceptions: `Color.moneySurplus` / `Color.moneyDeficit` (defined in `Views/Color+Money.swift`), iCloud sync-status system colors, and `.tint(.red)` for destructive controls (per `docs/tech-design-doc.md` §5.5).

#### 6.8.3 Localization — source strings and translations

Translations for all 38 App Store storefront locales are shipped and must be kept current. Every new user-facing string in a production view must:

- Use `Text("key", comment:)` or `String(localized: KEY, defaultValue:, comment:)`, keyed in `Localizable.xcstrings` — no hard-coded English literals; locale-invariant strings use `Text(verbatim:)`.
- Carry a translator-friendly `comment:`; the catalog must have no orphan keys.
- Be translated to all 38 storefront locales via the `scripts/translate_catalog/` pipeline (extract → translate → merge → validate) before the change ships to users.

The 38 storefronts are: `ar`, `ca`, `cs`, `da`, `de`, `el`, `en-AU`, `en-CA`, `en-GB`, `es`, `es-MX`, `fi`, `fr`, `fr-CA`, `he`, `hi`, `hr`, `hu`, `id`, `it`, `ja`, `ko`, `ms`, `nb`, `nl`, `pl`, `pt-BR`, `pt-PT`, `ro`, `ru`, `sk`, `sv`, `th`, `tr`, `uk`, `vi`, `zh-Hans`, `zh-Hant`. Human pseudo-loc and per-locale spot checks remain part of release verification (procedure in Appendix B of the audit linked above). Full keying rules are in `docs/tech-design-doc.md` §5.1.

#### 6.8.4 Mixpanel analytics for user actions

Every new user-initiated action that materially changes app state (a new destructive action, a new screen with a primary CTA, a new toggle whose value affects retention or feature usage) must ship with the corresponding `AnalyticsClient.track(...)` event per [`docs/analytics-spec.md`](analytics-spec.md), respecting the consent and no-PII rules in that spec. This applies to every change going forward — not only to a particular Mixpanel phase milestone. See `docs/tech-design-doc.md` §7 for the implementation boundary.

---

Implementation rules for all four concerns live in `docs/tech-design-doc.md` §§5.1–5.2, §5.5, and §7, and in `docs/analytics-spec.md`. The historical build-out features are tracked in `docs/product-features-planning.md` T-3 and T-8.

---

### 6.6 Data and Storage

- Persist data with **SwiftData** and sync across the user’s devices with **CloudKit**.

### 6.7 Carry-over behavior

These rules apply to every Budget. When carry-over is turned off for a budget (see product features), the carry-over amount is still computed and kept current internally but is **not displayed** in the UI for that budget. This ensures that toggling carry-over back on at any time produces an immediately correct, up-to-date figure without retroactive computation. Rules are **per budget**; there is no aggregation across budgets.

**Display (two separate numbers)**

The two numbers are computed and displayed independently — they are never merged into a single combined "available to spend" cap. Influence flows one direction only: the current period's *committed* overflow (overspend or add-funds excess) feeds into Carry-over (see "How carry-over moves" below). Carry-over never affects Remaining.

- **Remaining for the current Budget Period** — How much of *this period's* allocation is left. Live as expenses are added, edited, or deleted within the current period. May go negative (overspend) or above the allocation (add-funds excess via [F-6.01](product-features-planning.md)). Example: with a $20/day allocation, the primary "left to spend" for today shows amounts derived only from today's $20 and today's expenses, not mixed into a single combined cap.
- **Carry-over** — A separate, signed cumulative total that reflects how far ahead or behind the user is relative to their recurring allocation. Sum of completed prior active periods, plus the *committed* portion of the current period's overflow (see asymmetric live coupling below). Carried across Budget Periods until it is reset. Copy and formatting should read cleanly for both directions (e.g. surplus vs deficit); exact strings are a design choice.

**How carry-over moves**

Carry-over has two components, both contributing to the displayed value:

1. **Sum across completed prior active periods.** At each **Budget Period** boundary (e.g. each new day for a daily budget), the outcome of the period that just ended folds in: `(allocation for that period − total expenses counted against that period)` is added to the running carry-over. Example: carry-over was a $5 deficit; allocation for the day was $20; the user spent $18. The $2 unspent vs that allocation reduces the deficit, so carry-over becomes a $3 deficit before the new period's expenses apply.

2. **Asymmetric live coupling with the current period.** While a period is in progress, the current period's contribution flows into Carry-over **only when it has crossed out of `[0, allocation]`** — i.e., only when the user has *committed* an overshoot in either direction. This is the asymmetric live coupling rule:

   - **Overspend (Remaining < 0).** The deficit is immediately reflected in Carry-over. Example: daily $20 budget, +$5 carry-over from prior days, $10 already spent today. User logs an $11 expense → Remaining becomes −$1, Carry-over becomes +$4 instantly. Deleting that expense snaps Carry-over back to +$5.
   - **Add-funds excess (Remaining > allocation, see [F-6.01](product-features-planning.md)).** The excess above allocation is immediately reflected in Carry-over. Example: daily $20 budget, user adds $30 of funds → Remaining becomes $50, Carry-over absorbs the +$30 excess.
   - **Ordinary mid-period slack (0 ≤ Remaining ≤ allocation).** Carry-over does **not** change. The slack remains *provisional* — the user might still spend more before the period closes — and only flows into Carry-over when the period actually completes (per rule 1 above).

   **Rationale.** Committed actions (overspend, deliberate add-funds) reflect real user decisions and belong in the cumulative position immediately. Provisional slack waits for the period to close so the user does not over-rely on a mid-day "ahead" reading they might still spend down. Loss-aversion: bad news lands live; good news waits for the period close.

   **Post-end (`now > endDate`) collapses to symmetric.** When the budget has ended, there is no future period close, so the full final-period contribution (positive or negative) folds into Carry-over immediately. This is what makes the chip "frozen at final tally."

   **Paused periods contribute 0.** A paused period's allocation is not credited and its expenses are not debited. The asymmetric rule does not apply while the current period is paused — Carry-over is whatever it was at the most-recent pause moment (modulo retroactive edits to prior active periods).

- **Positive and negative** carry-over amounts both carry forward according to these rules until reset.

**Resetting carry-over**

- **Manual** — The Budget detail screen provides a control to reset carry-over to zero (with confirmation). Per-budget only. This is a "carry-over only" reset: no expenses are deleted.

**Distinct destructive operations on a Budget**

Three operations exist with different blast radii — do not conflate them:


| Operation            | Trigger                                                    | Effect                                                                                                                   |
| -------------------- | ---------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| **Reset Carry-Over** | Budget detail screen → toolbar overflow Menu → "Reset Carry-Over…" | Sets `lastResetDate = now` on the budget, bumps `lastModified`. The live walker treats all periods whose end is at or before `lastResetDate` as excluded, producing a carry-over of zero from that moment forward. No `ExpenseItem`s are deleted.              |
| **Reset Budget**     | Budget detail screen → toolbar Menu → "Reset Budget…"      | Deletes every `ExpenseItem` for this budget AND sets `lastResetDate = now`, bumps `lastModified`. If the budget is currently paused, the same atomic write also inserts a `.resume` `LifecycleEvent` so the post-reset state is active. The `Budget` entity itself remains. See F-2.02. |
| **Delete Budget**    | Add/Edit Budget sheet (Edit mode) → "Delete Budget" button | Removes the `Budget` entity and cascade-deletes all its `ExpenseItem`s and child `AllocationChange` / `LifecycleEvent` rows. See F-2.03.                                      |


All three require a confirmation dialog. "Reset Budget" and "Delete Budget" are **irreversible**.

- **Carry-over optional** — A budget may have carry-over turned off (see product features); when off, the carry-over amount is maintained internally but not shown for that budget. Toggling carry-over back on surfaces the current, already-computed figure.

---

## 7. Technical Foundations

*High-level technical decisions that constrain all downstream work. More specifics wil be worked out during feature development.*

The companion technical reference for implementation and tooling is [tech-design-doc.md](tech-design-doc.md) (architecture, SwiftData/CloudKit, and related engineering choices).

### 7.1 Language and Frameworks

- Latest stable Swift version.
- Prefer SwiftUI, unless the capability does not exist. 
- Prefer latest Swift testing infrastructure.

### 7.2 Data Model (High-Level)

High-level entities include:

- **Budget** — A spending allowance that repeats (daily, weekly, biweekly, monthly) or spans a fixed window (**Specific Dates** trip-style budgets). Carries configuration for Budget Period, allocation history (`AllocationChange`), **currency (per budget)**, optional `startDate` / `endDate` bounds, lifecycle events (pause/resume via `LifecycleEvent`), optional emoji **icon**, and carry-over toggle.
- **Expense Item** — A single expense or add-funds entry. Amount is signed at persistence (`negative` = add funds). Optional `expenseType` field exists in schema; user-facing editor not yet shipped (F-6.02).

### 7.3 Third-Party Dependencies Policy

- Prefer using Apple's libraries and frameworks to external.
- All dependencies should be canonical and industry best-practice.
- All dependencies must be actively maintained.
- All dependencies should pull the latest version.

### 7.4 General Architecture Constraints

- Except for leveraging Apple's CloudKit and similar cloud services that are free to the developer, there will be no backend.

---

## 8. Design Foundations

### 8.1 Visual Design Principles

- Adhere to Apple's Human Interface Guidelines and latest industry best practices. If the two conflict, ask for clarification. 
- Visual design should be minimalistic and elegant. 
- Use default Apple typography, spacings, margins, etc.

### 8.2 Branding

- Vibes: Simple, elegant, and cute.

### 8.3 Information Architecture

Screens:

- Budgets screen — List of Recurring Budgets with remaining for the current Budget Period
- Budget screen — List of Expense Items for one Budget
- Add/Edit Budget screen — Create or edit a Budget (entity).
- Add/Edit/View Expense Item screen — Create, edit, or view an Expense Item (entity).
- Settings screen

In strict-opt-in analytics jurisdictions, a first-run consent sheet may appear before the user creates their first budget; ongoing opt-in/out lives in Settings (see [analytics-spec.md](analytics-spec.md) and F-8.02).

---

## 9. Open Questions

- None

---

## 10. Appendix

### 10.1 Glossary

- Recurring Budget (AKA Budget) - An allocation of available spending that repeats the allocation at regular time intervals, or — for **Specific Dates** budgets — a single fixed window with one allocation. The supported period values are defined in app code (see `BudgetPeriod` or equivalent).
- Expense Item (AKA Expense or Transaction) - A specific expense.
- **Specific Dates budget** — A one-window trip-style budget: required start and end dates, one allocation for the whole window, no recurrence, no carry-over chip. Distinct from a recurring budget whose start/end dates bound its lifetime.
- **Paused budget** — A recurring budget temporarily stopped via Pause; reversible with Resume. Distinct from a budget past its terminal **end date**, which cannot be resumed.
- Budget Period - The repeating time interval the Budget allocates funds to. The canonical set of cases and their string values are defined in app code (see `BudgetPeriod` or equivalent).
- Carry-over Amount (AKA CarryOver) - A per-budget, signed cumulative total: surplus (under-spent relative to allocation over time) or deficit (over-spent). It is **shown separately** from “remaining for this Budget Period” (which is not adjusted by carry-over for display). Computed live per [§6.7](#67-carry-over-behavior) as the sum of completed prior active periods plus the *committed* portion of the current period's overflow (asymmetric live coupling: overspend and add-funds excess land immediately; ordinary mid-period slack waits for the period to close). Can be cleared manually via Reset Carry-Over or Reset Budget.
- Reset Budget - A destructive action on the Budget detail screen that deletes every Expense Item for a given Budget and sets `lastResetDate = now` so carry-over starts from zero, while leaving the Budget entity itself intact. If the budget is currently paused at reset time, the same atomic write also inserts a `.resume` `LifecycleEvent` so the post-reset state is active rather than a paused-but-empty limbo. Distinct from Reset Carry-Over (which only resets carry-over) and Delete Budget (which removes the Budget entity and cascades to its Expense Items). See §6.7 and F-2.02.
- Reset Carry-Over - A per-budget action on the Budget detail screen that sets `Budget.lastResetDate = now` so the live-walker excludes all prior periods, producing a carry-over of zero from that moment forward. No Expense Items are deleted. Distinct from Reset Budget and Delete Budget. See §6.7 and F-2.02.

### 10.2 References

None

### 10.3 Revision History


| Version | Date       | Author   | Changes          |
| ------- | ---------- | -------- | ---------------- |
| 1.2     | 2026-05-31 | Jimmy Ho | §7.2 expanded data model (Specific Dates, LifecycleEvent, icon, add-funds); §8.3 analytics consent sheet note; §10.1 glossary entries for Specific Dates and Paused budget. |
| 1.1     | 2026-05-31 | Jimmy Ho | §6.8 is now the canonical home for the per-change maintenance requirements of all four cross-cutting concerns. Migrated the detailed maintenance checklists (Dynamic Type, VoiceOver, Dark Mode, Localization source-strings + translations, Mixpanel user-action analytics) from `product-features-planning.md` F-3.01/F-3.02/F-3.03/F-3.05/F-8.02 into new subsections §6.8.1–§6.8.4. Those feature entries are reframed as completed initial build-outs. |
| 1.0     | 2026-05-03 | Jimmy Ho |                  |
| 0.2     | 2026-05-03 | Jimmy Ho | §6.8 Cross-cutting ongoing concerns (Accessibility, source-string coverage, translations queue, Mixpanel user-action analytics); §6.4 and §6.5 cross-references to §6.8. |
| 0.1     | 2026-04-10 | Jimmy Ho | Initial template |


