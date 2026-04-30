# Product Features Planning

**Version:** 0.2  
**Last Updated:** 2026-04-30
**Author/Owner:** Jimmy Ho

For north-star vision, guiding principles, and global constraints, see [main-prd.md](main-prd.md).

---

## Themes

### T-1: Technical Foundations

#### Features

##### F-1.01: App Scaffolding

- **Status:** Implemented. Xcode project, test targets, and GitHub repo exist.
- **Description:** Basic app created.
- **Acceptance Criteria:**
  - Xcode project created with main code folder and tests folders scaffolded.
  - git repo created and linked to GitHub
  - Empty app compiles and runs.
- **Edge Cases / Notes:** None
- **Dependencies:** None

##### F-1.02: Data Architecture

- **Status:** Implemented. Implemented by change `data-architecture`; SwiftData models with CloudKit sync are in place.
- **Description:** Database schema created to support entire product roadmap. Persistence uses **SwiftData** with **CloudKit** sync.
- **Acceptance Criteria:**
  - Database schema instantiated in the app.
  - SwiftData models configured for **CloudKit** container sync across the user’s devices.
- **Edge Cases / Notes:** None
- **Dependencies:** None

---

### T-2: Fundamentals

#### Features

##### F-2.01: Budgets screen

- **Status:** Implemented. Implemented by change `budgets-screen` and `finish-budgets-screen`.
- **Description:** Top-level screen: list of Recurring Budget (entity) rows and where the user stands.
- **Acceptance Criteria:**
  - Name of budget field
  - **Remaining for current Budget Period** field — this period’s allocation minus expenses for this period only; **not** merged with carry-over for display (see [main-prd.md §6.7](main-prd.md#67-carry-over-behavior)).
  - **Carry-over** field — separate signed cumulative carryover per [main-prd.md §6.7](main-prd.md#67-carry-over-behavior).
  - **Drag-to-reorder budgets** — user can reorder the list via standard iOS edit-mode drag (and long-press drag where the platform supports it); the order is persisted via `Budget.sortOrder` so it survives app relaunch and syncs across the user's iCloud-paired devices.
  - This **Budgets screen** is the top level of the app.
- **Edge Cases / Notes:** None
- **Dependencies:** None

##### F-2.02: Budget screen

- **Status:** Implemented (excluding F-6.01). Core screen implemented by change `budget-detail-screen`; tap-to-edit on expense rows implemented by change `expense-row-push-navigation`.
- **Description:** Screen that lists Expense Items for a single Budget (entity).
- **Acceptance Criteria:**
  - Shows vertical scrolling list of transactions as a list of most-recent to least-recent.
  - Shows the Budget’s name at top of the screen (navigation title).
  - Shows **Remaining for current Budget Period** and **Carry-over** consistent with [main-prd.md §6.7](main-prd.md#67-carry-over-behavior) and F-2.01.
  - **Status header** — large monospaced remaining amount (deficit-tinted when negative), period label, fuel-gauge `RemainingBar`, and — when carry-over is enabled — an inline `CarryOverChip` and a small **Reset** button for the manual carry-over reset.
  - **Adaptive header layout** — remaining amount and period label render side-by-side below `.xxxLarge` Dynamic Type; stacked vertically at `.xxxLarge` and above. Row spacing scales via `@ScaledMetric`.
  - **Primary Add Expense action** — a full-width `.borderedProminent` button always visible within the screen, presenting `SheetRoute.addExpense(budget)` for this specific budget.
  - **Tap-to-edit expense row** — tapping an expense row pushes `AddEditExpenseView` in Edit mode via `AppRoute.expenseDetail(expense)` (push navigation, standard back-button return). Implemented by change `expense-row-push-navigation`.
  - **Toolbar overflow Menu** (`ellipsis.circle`, top-trailing) hosting:
    - **Edit Budget** — opens the Add/Edit Budget sheet in Edit mode.
    - **Reset Budget…** (destructive) — deletes every `ExpenseItem` for this budget, zeros `carryOverAmount`, and bumps timestamps in a single `ModelContext.save()`. The `Budget` entity itself is **not** deleted. Gated by a confirmation dialog whose body is a single static localized string (no expense count in copy). See [main-prd.md §6.7](main-prd.md#67-carry-over-behavior) for the distinction between Reset Budget, Reset Carry-Over, and Delete Budget.
  - **Reset Carry-over** control with confirmation; clears only this budget’s carry-over (per [main-prd.md §6.7](main-prd.md#67-carry-over-behavior)).
  - **Delete Expense Item** — swipe-to-delete on a row. A full trailing swipe or a tap on the revealed destructive button immediately deletes the expense; no confirmation dialog is presented.
  - **Period-aware expense sections** — expenses are split into a **Current ⟨period⟩** section (items in the current Budget Period, with a section total) and a **Past ⟨period⟩** section (earlier items). Contextual empty captions handle the current-period-empty and zero-expense cases.
  - For each Expense Item, shows the following fields:
    - Date and time (relative: “Today HH:mm” / “Yesterday HH:mm” / locale-aware beyond yesterday)
    - Amount of expense (absolute value; `Color.moneySurplus` tint for add-funds entries per F-6.01 display path)
    - Name of expense (or an italic “Untitled expense” placeholder when nil)
  - **Lifecycle refresh** on task initialization, `scenePhase == .active`, and `onChange(of: budget.expenseItems.count)`.
  - **VoiceOver** — composed accessibility labels on the header (on-budget and over-budget variants) and on each expense row (standard and add-funds variants).
- **Edge Cases / Notes:** The add-funds display path for `ExpenseItem.isAddFunds` is present but no UI to create one exists until F-6.01 (PAUSED).
- **Dependencies:** F-2.01

##### F-2.03: Add/Edit Budget screen

- **Status:** Implemented (excluding paused Reset Cadences). Implemented by change `add-edit-budget-screen`; uses Foundation's system currency catalog (`Locale.commonISOCurrencyCodes` + `Locale.localizedString(forCurrencyCode:)`). Delete Budget implemented by change `delete-budget-button`.
- **Description:** Screen to create or edit a Budget (entity).
- **Acceptance Criteria:**
  - Same screen used to create and edit.
  - Entry point added to **Budgets screen** to create a Budget (entity).
  - Entry point added to **Budget screen** to edit that Budget (entity).
  - **Delete Budget** — Edit mode only. A destructive bordered button appears beneath the form cards when editing an existing budget. Tapping it presents a confirmation dialog with the message "This action cannot be undone." Confirming the dialog deletes the `Budget` and (via the existing `Budget → ExpenseItem` cascade-delete rule) all of its `ExpenseItem` rows in a single `ModelContext.save()`. The sheet is then dismissed and the row disappears reactively from the Budgets list. Add mode does not show this button.
  - Fields:
    - ID: Arbitrary internal identifier, not shown to user. 
    - Name — defaults to empty string (user-editable); the field shows `"Budget"` as a placeholder but the draft value is blank so Save is disabled until the user types a name. In Add mode the Name field auto-focuses (keyboard appears) when the sheet opens.
    - Time Period (daily, weekly, biweekly, monthly). Defaults to daily.
    - Allocation. Defaults to blank (no amount until the user enters one); Save stays disabled until a positive amount is entered. The Allocation card prefixes the numeric field with a currency symbol/code label driven by `AppSettings.currencyDisplay` (symbol / code / code+symbol).
    - **Currency (per budget)** — Each Budget has its own currency. Defaults to locale's currency; USD if unable to determine at all.
    - **Carry-over reset cadence** _(PAUSED — see note below)_ — How often cumulative carry-over is cleared **automatically**. Options: **weekly**, **biweekly**, **monthly**, **quarterly**, or **never** (no automatic reset; user uses manual reset only). **Quarterly** and **never** are not Budget Periods; they apply only here. Valid options depend on Budget Period (each cadence must be broader than the period; see [main-prd.md §6.7](main-prd.md#67-carry-over-behavior)). **Defaults** for new budgets: daily → weekly; weekly → monthly; biweekly → quarterly; monthly → quarterly. Scheduled resets align to **period boundaries** (first boundary after the interval), never mid-period.
    - When **Time Period** is **monthly**, the default reset cadence is **quarterly**. Carry-over accumulates across months and resets every quarter. _(PAUSED — see note below.)_

> [!NOTE]
> **PAUSED — Reset Cadences feature is not in scope.** The carry-over reset cadence field and scheduled-reset flow are paused. Acceptance criteria for current work MUST NOT depend on Reset Cadence UI; treat any default as `.never`. Existing description is retained for future reference; **do not include a Reset Cadence control in the Add/Edit Budget sheet while paused.**

- **Edge Cases / Notes:** None
- **Dependencies:** F-2.01

##### F-2.04: Add/Edit/View Expense Item screen

- **Status:** Implemented (changes `add-edit-expense-screen`, `edit-expense-omit-cancel`)
- **Description:** A full screen (or partial screen) that shows all the editable fields of an Expense Item (entity).
- **Acceptance Criteria:**
  - Shows editable name of expense (optional)
  - Shows editable amount of expense (required)
  - Shows date and time (prefilled with current date and time)
  - Same screen is used for add, edit, and view use cases.
  - No Edit Mode. User should be able to edit fields in place without having to toggle modes.
  - **Add mode** shows a leading Cancel button (dismisses without saving) and a trailing Save button.
  - **Edit mode** shows only a trailing Save button; the system back button serves as the discard path.
- **Edge Cases / Notes:**
  - The screen treats Edit and View as a single mode (per the "No Edit Mode" AC); fields are always directly editable without a mode toggle. "View" means opening the Edit sheet for an existing expense.
  - Edit-mode Save preserves the sign of `ExpenseItem.amount`, so existing add-funds rows (F-6.01) survive an edit without flipping to a positive expense. Add mode unconditionally inserts a non-negative amount; the Add Funds toggle UI is part of F-6.01's future change.
  - Omitting Cancel in Edit mode avoids redundancy with the navigation back button and reduces toolbar clutter on the narrow pushed view.
- **Dependencies:** F-2.02

##### F-2.05: Settings screen

- **Status:** Implemented. Implemented by change `settings-screen`.
- **Description:** A modal Settings sheet accessible from the Budgets navigation bar. Contains six sections with functional controls, a Done button, and no ViewModel (plain SwiftUI view).
- **Acceptance Criteria:**
  - A Settings entry-point button is placed in the canonical location in the Budgets navigation bar; tapping it presents a modal sheet.
  - **Budgets section** — Default Carry-Over toggle: bound to `AppSettings.defaultCarryOverEnabled`; see F-2.07 for carry-over semantics.
  - **Calendar section** — Week Starts On picker: shows a confirmation alert before applying the selected weekday; confirmed value writes to `AppSettings.weekStartDay`; see F-5.01 for week-start semantics.
  - **Display section** — Currency Display preference picker: bound to `AppSettings.currencyDisplay`; picker row labels show `"<option label> — <locale-aware example>"` where the example is derived live from `Locale.autoupdatingCurrent` using the canonical `Decimal.formatted(currencyCode:display:locale:)` formatter; value is persisted to `NSUbiquitousKeyValueStore` and applied app-wide to all monetary rendering; see F-3.04 for currency display requirements.
  - **iCloud Sync Status section** — Shows a tri-state row derived from `SyncStatus.rowState`: `.checking` (spinner), `.available` (green checkmark icon, syncing), `.paused` (orange exclamation icon, local-only container despite iCloud sign-in), `.unavailable` (orange x icon, not signed in); section footer appears only for `.unavailable` and `.paused` states; account status is re-queried live on `CKAccountChanged` notifications.
  - **Support section** — "Send Feedback" (opens `mailto:` link), "Rate the App" (invokes `requestReview()`), "Privacy Policy" (opens URL in browser; URL is TBD until launch).
  - **About section** — Displays app version and build number from `CFBundleShortVersionString` / `CFBundleVersion`.
  - Done button dismisses the sheet.
- **Edge Cases / Notes:** `privacyPolicyURL` is intentionally left as a TODO placeholder until the URL is decided before launch.
- **Dependencies:** F-2.01, F-2.07, F-3.04, F-5.01

##### F-2.06: First-run empty state

- **Status:** Implemented. Empty state included in the `budgets-screen` change (ContentUnavailableView with create-budget CTA).
- **Description:** On first launch when the data store contains no budgets, the **Budgets screen** displays a first-run empty state with a clear primary action to create a budget. No placeholder or seed Budget is inserted by the app.
- **Acceptance Criteria:**
  - After first launch with an empty store, the **Budgets screen** shows its empty-state view (title, short description, and a primary "Create a budget" CTA) — NOT a blank or unlabeled screen.
  - No `Budget` entity is created by the app as part of launch; any Budget in the store was created by the user.
  - The empty state is rendered whenever the Budgets `@Query` returns zero rows, so the same view is shown for any future state in which the store transiently presents zero budgets (e.g., during initial CloudKit hydration on a fresh install of an existing iCloud account).
- **Edge Cases / Notes:** The empty-state UI itself ships under F-2.01; F-2.06 is the first-launch contract.
- **Dependencies:** F-2.01

##### F-2.07: Carry-over toggle switch

- **Status:** Implemented. Per-budget toggle implemented as part of the `add-edit-budget-screen` change; global default implemented as part of the Settings screen.
- **Description:** Every budget can have the carry-over calculation turned off. 
- **Acceptance Criteria:**
  - Add/Edit Budget screen has a toggle to turn on/off the carry-over of the prior balances.
  - In Add mode, the carry-over toggle defaults to the current value of the global default carry-over setting in Settings (`AppSettings.defaultCarryOverEnabled`).
  - Settings screen has a global setting to default all new Budgets with carry-over turned on or off. It is turned on by default.
  - This setting is stored in `NSUbiquitousKeyValueStore` and syncs automatically across the user's iCloud-connected devices.
- **Edge Cases / Notes:** None
- **Dependencies:** F-1.02, F-2.02, F-2.05

---

### T-3: Internationalization and Accessibility

#### Features

##### F-3.01: Dynamic Type

- **Status:** Partially implemented. All shipped screens use semantic text styles, `@ScaledMetric`, and adaptive layouts; not formally audited per-screen.
- **Description: Dynamic Type is supported** 
- **Acceptance Criteria: None**
- **Edge Cases / Notes:** None
- **Dependencies:** None

##### F-3.02: VoiceOver

- **Status:** Implemented (static + per-screen audit complete; pending interactive walkthrough). Audited and remediated under [docs/audits/2026-04-30-loc-voiceover-audit.md](audits/2026-04-30-loc-voiceover-audit.md). All shipped screens provide composed accessibility labels and hints; the status header on the Budget detail screen now carries `.isHeader` for rotor navigation; `swipeActions` are paired with explicit `.accessibilityAction(named:)` so VoiceOver users can delete via the rotor; custom composite controls (`RemainingBar`, `CarryOverChip`, currency-picker rows, current-period section header) collapse to single VO elements; destructive controls (Delete Budget, Delete Expense, Reset Budget, Reset Carry-Over, swipe delete) speak the consequence via `.accessibilityHint`.
- **Description: VoiceOver is supported**
- **Acceptance Criteria:**
  - All necessary UI elements have accessibility labels to support VoiceOver.
  - Custom composite views (e.g. carry-over chip, currency picker rows, current-period section header) read as single VoiceOver elements with composed labels rather than as multiple static-text fragments.
  - Destructive controls (Reset Budget, Reset Carry-Over, Delete Budget, Delete Expense, swipe-to-delete on an expense row) carry an `accessibilityHint` describing the irreversible consequence.
  - `swipeActions` are paired with `.accessibilityAction(named:)` mirroring the gesture so VoiceOver users can invoke them via the rotor.
- **Edge Cases / Notes:** Live VoiceOver walkthrough and pseudo-loc smoke procedures are documented in [Appendices B and C of the audit](audits/2026-04-30-loc-voiceover-audit.md); they are delegated to the human verifier on real hardware.
- **Dependencies:** F-3.03

##### F-3.03: Internationalization of text

- **Status:** Partially implemented. **English source coverage** is complete and audited under [docs/audits/2026-04-30-loc-voiceover-audit.md](audits/2026-04-30-loc-voiceover-audit.md): every user-facing string in production views is keyed in `Localizable.xcstrings` with a translator `comment:`, no hard-coded literals remain, and shared keys (`common.action.cancel`) eliminate duplicate copy across surfaces. **Real translations** for additional languages have not yet been produced.
- **Description:** All user-facing text is keyed and translatable; once translations are produced, all labels change automatically to match the device's locale.
- **Acceptance Criteria:**
  - All Apple-supported languages have translations for all labels.
  - All labels change automatically to match the device's locale.
  - Every user-facing string in production views uses `Text("key", comment:)` or `String(localized: KEY, defaultValue:, comment:)`; no hard-coded English literals remain.
  - The catalog has no orphan keys and every key carries a translator-friendly `comment:`.
- **Edge Cases / Notes:** Pseudo-localization smoke procedure is documented in [Appendix B of the audit](audits/2026-04-30-loc-voiceover-audit.md). Translation rollout to additional locales is the remaining work for this feature.
- **Dependencies:** None

##### F-3.04: Internationalization of currency

- **Status:** Partially implemented. Per-budget currency picker (`CurrencyPickerView`) and locale-aware formatting shipped with `add-edit-budget-screen`; currency display preference shipped with `settings-screen`. Full i18n of picker display names depends on F-3.03.
- **Description:** Currency is **per Budget** (entity) — see **Add/Edit Budget screen** (F-2.03) — not a single global app default. This feature covers formatting, symbols, and the currency catalog used when choosing a Budget’s currency.
- **Acceptance Criteria:**
  - **Add/Edit Budget screen** includes a currency picker; all supported currency codes are available there (not on **Settings screen** as a global override). _(Implemented by `add-edit-budget-screen` change.)_
  - Amounts and symbols in the UI respect **each Budget’s** selected currency and the user’s locale formatting rules.
  - Currency catalog (codes, symbols, localized names) is sourced from outside our application source — either from Foundation’s system catalog (`Locale.commonISOCurrencyCodes` plus `Locale.localizedString(forCurrencyCode:)`) or from a project-owned data file (e.g. YAML) when the app needs to diverge from the system catalog. The Add/Edit Budget screen ships the system-catalog path.
  - The display name of each currency in the picker is internationalized. _(Implemented by `add-edit-budget-screen` change.)_
- **Edge Cases / Notes:** None
- **Dependencies:** F-2.03, F-3.03

##### F-3.05: Dark Mode

- **Status:** Partially implemented. Named color assets with light/dark appearances are used on all shipped screens; semantic system colors throughout; not formally audited per-screen.
- **Description: Dark mode is supported.** 
- **Acceptance Criteria:** 
- **Edge Cases / Notes:** None
- **Dependencies:** None

---

### T-4: Cute Shit

#### Features

##### F-4.01: Technical - Refactor support multiple color themes.

- **Status:** Open
- **Description:** 
- **Acceptance Criteria:**
- **Edge Cases / Notes:**
- **Dependencies:**

##### F-4.02: Support multiple color themes

- **Status:** Open
- **Description: For example, feminine, masculine, dogs, cats, whatever.** 
- **Acceptance Criteria:**
- **Edge Cases / Notes:**
- **Dependencies:**

##### F-4.03: Support an icon for each Budget

- **Status:** Open
- **Description: User can pick an icon to help distinguish each Budget**
- **Acceptance Criteria:**
  - **Add/Edit Budget screen** includes icon selection for each Budget (entity).
  - **Budget screen** and **Budgets screen** display the icon where applicable.
  - If feasible, use LLM to guess default icon for each Budget.
  - User can pick emoji
  - If feasible, user can pick from Apple-native emoji-like icons that can be custom-generated.
- **Edge Cases / Notes:**
- **Dependencies:**

##### F-4.04: Support for photo upload for icon for each Budget

- **Status:** Open
- **Description:** 
- **Acceptance Criteria:**
- **Edge Cases / Notes:**
- **Dependencies:**

---

### T-5: Configurations

#### Features

##### F-5.01: Configurable start of week.

- **Status:** Implemented. `AppSettings.weekStartDay` with Settings picker and confirmation alert; implemented by change `settings-screen`.
- **Description:** Choose start day of week for weekly Budgets.
- **Acceptance Criteria:**
  - Default value is determined by locale's official week starting day. For example, Sunday in the USA, Monday in most of Europe. 
  - Configurable to be different. Will cascade to all existing Budgets. 
  - Display pop-up to acknowledge that existing Budgets will be affected.
  - This setting is stored in `NSUbiquitousKeyValueStore` and syncs automatically across the user's iCloud-connected devices.
- **Edge Cases / Notes:**
- **Dependencies:**

---

### T-6: Miscellaneous

#### Features

##### F-6.01: Allow manually adding funds

- **Status:** Partially implemented. Model layer done (`isAddFunds`, `displayAmount` on `ExpenseItem`, negative-amount convention, edit sign preservation in `AddEditExpenseViewModel`). Budget detail screen shows add-funds rows with `Color.moneySurplus` tint and VoiceOver labels. UI toggle on the Add Expense screen to *create* an add-funds entry is not yet shipped.
- **Description:** User can add a transaction where the amount adds to available funds instead of subtract from it. 
- **Acceptance Criteria:**
- **Edge Cases / Notes:**
- **Dependencies:**

##### F-6.02: Expense Type on Expense Items

- **Status:** Partially implemented. Schema done: `expenseType: String?` on `ExpenseItem` (persisted in SchemaV1). No user-facing editor shipped yet.
- **Description:** 
  - On each Expense Item, allow user to specify an Expense Type.  
  - User can select from "Cash", "Credit Card", "Debit Card", but can also choose to type in their own value.
  - If user types in own value, that is stored as a predefined value in the future.
- **Acceptance Criteria:**
- **Edge Cases / Notes:**
- **Dependencies:**

##### F-6.03: App Store rating prompt

- **Status:** Open
- **Description:** Prompt the user to rate the app in the App Store after meaningful product use and/or after a minimum elapsed time period.
- **Acceptance Criteria:**
  - The app requests an App Store rating only after eligibility conditions are met, based on meaningful usage and/or elapsed time.
  - Eligibility thresholds and exact trigger formula are explicitly **TBD** and will be finalized later.
  - Prompting behavior is respectful and non-intrusive (not shown too frequently, and not shown on every launch).
  - The app tracks prompt outcomes so a recent dismissal or rating action prevents immediate re-prompting.
- **Edge Cases / Notes:** Final trigger logic, cooldown duration, and definition of "meaningful usage" are **TBD**.
- **Dependencies:** None

---

### T-7: AI Features

#### Features

##### F-7.01: Receipt scanning via camera

- **Status:** Open
- **Description:** User takes a photo of a receipt; on-device machine vision extracts the amount (and optionally merchant name / date) to pre-fill an Expense Item.
- **Acceptance Criteria:**
- **Edge Cases / Notes:**
- **Dependencies:** F-2.04

##### F-7.02: Voice input to add an Expense Item

- **Status:** Open
- **Description:** User speaks via Siri and/or in-app voice input; Apple's on-device NLP parses the utterance into an Expense Item (amount, name, date/time).
- **Acceptance Criteria:**
- **Edge Cases / Notes:**
- **Dependencies:** F-2.04

##### F-7.03: Voice query for Budget status

- **Status:** Open
- **Description:** User speaks via Siri and/or in-app voice input to ask about a Budget's current status; the app responds with the **Remaining for current Budget Period** amount and the separate **Carry-over** amount.
- **Acceptance Criteria:**
- **Edge Cases / Notes:**
- **Dependencies:** F-2.01, F-2.02

---

### T-8: Analytics and Observability

#### Features

##### F-8.01: Basic analytics reporting via OSLogger

- **Status:** Partially implemented in data model creation code. No other coverage. 
- **Description:** Analytics reporting as OSLogger is meant to be used.
- **Acceptance Criteria:** 
  - Coverage is 100% of the things that OSLogger is meant to log, leaning towards leaner logging.
- **Edge Cases / Notes:**
- **Dependencies:** None

##### F-8.02: Mixpanel basic analytics

- **Status:** Open
- **Description:** 
- **Acceptance Criteria:**
- **Edge Cases / Notes:**
- **Dependencies:** None

##### F-8.03: Mixpanel advanced analytics

- **Status:** Open
- **Description:** 
- **Acceptance Criteria:**
- **Edge Cases / Notes:**
- **Dependencies:** F-8.02

