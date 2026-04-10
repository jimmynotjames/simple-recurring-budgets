# Product Features Planning

**Version:** 0.1
**Last Updated:** 2026-04-10
**Author/Owner:** Jimmy Ho

For north-star vision, guiding principles, and global constraints, see [main-prd.md](main-prd.md).

---

## Themes

### T-1: Technical Foundations

#### Features

##### F-1.01: App Scaffolding

- **Status:** Open
- **Description:** Basic app created.
- **Acceptance Criteria:**
  - Xcode project created with main code folder and tests folders scaffolded.
  - git repo created and linked to GitHub
  - Empty app compiles and runs.
- **Edge Cases / Notes:** None
- **Dependencies:** None

##### F-1.02: Data Architecture

- **Status:** Open
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

- **Status:** Open
- **Description:** Top-level screen: list of Recurring Budget (entity) rows and where the user stands.
- **Acceptance Criteria:**
  - Name of budget field
  - **Remaining for current Budget Period** field — this period’s allocation minus expenses for this period only; **not** merged with Over/Under for display (see [main-prd.md §6.7](main-prd.md#67-overunder-carryover-behavior)).
  - **Over/Under** field — separate signed cumulative carryover per [main-prd.md §6.7](main-prd.md#67-overunder-carryover-behavior).
  - **Delete Budget** — swipe-to-delete on a row with confirmation
  - This **Budgets screen** is the top level of the app.
- **Edge Cases / Notes:** None
- **Dependencies:** None

##### F-2.02: Budget screen

- **Status:** Open
- **Description:** Screen that lists Expense Items for a single Budget (entity).
- **Acceptance Criteria:**
  - Shows vertical scrolling list of transactions as a list of most-recent to least-recent.
  - Shows the Budget’s name at top of the screen.
  - Shows **Remaining for current Budget Period** and **Over/Under** consistent with [main-prd.md §6.7](main-prd.md#67-overunder-carryover-behavior) and F-2.01.
  - **Reset Over/Under** control with confirmation; clears only this budget’s Over/Under (per [main-prd.md §6.7](main-prd.md#67-overunder-carryover-behavior)).
  - **Delete Expense Item** — swipe-to-delete on a row with confirmation
  - For each Expense Item, shows the following fields:
    - Date and time
    - Amount of expense
    - Name of expense
- **Edge Cases / Notes:** None
- **Dependencies:** F-2.01

##### F-2.03: Add/Edit Budget screen

- **Status:** Open
- **Description:** Screen to create or edit a Budget (entity).
- **Acceptance Criteria:**
  - Same screen used to create and edit.
  - Entry point added to **Budgets screen** to create a Budget (entity).
  - Entry point added to **Budget screen** to edit that Budget (entity).
  - Fields:
    - ID: Arbitrary internal identifier, not shown to user. 
    - Name (optional)
    - Time Period (daily, weekly, biweekly, monthly). Defaults to daily.
    - Allocation. Defaults to 10.
    - **Currency (per budget)** — Each Budget has its own currency. Defaults to locale's currency; USD if unable to determine at all.
    - **Over/Under reset cadence** — How often cumulative Over/Under is cleared. Allowed options are bounded by Budget Period up to **monthly** maximum (per [main-prd.md §6.7](main-prd.md#67-overunder-carryover-behavior)). Default: next broader rhythm than Budget Period, capped at monthly (e.g. daily → weekly; weekly → monthly; monthly → monthly).
    - When **Time Period** is **monthly**, show inline **explanatory copy** that Over/Under does not carry across months (aligned with monthly reset).
- **Edge Cases / Notes:** None
- **Dependencies:** F-2.01


##### F-2.04: Add/Edit/View Expense Item screen

- **Status:** Open
- **Description:** A full screen (or partial screen) that shows all the editable fields of an Expense Item (entity).
- **Acceptance Criteria:**
  - Shows editable name of expense (optional)
  - Shows editable amount of expense (required)
  - Shows date and time (prefilled with current date and time)
  - Same screen is used for add, edit, and view use cases.
  - No Edit Mode. User should be able to edit fields in place without having to toggle modes.
- **Edge Cases / Notes:** None
- **Dependencies:** F-2.02

##### F-2.05: Settings screen

- **Status:** Open
- **Description:** Settings screen; content blank to start.
- **Acceptance Criteria:**
  - Entry point button is placed in canonical place for apps of this kind.
- **Edge Cases / Notes:** None
- **Dependencies:** F-2.01

##### F-2.06: First-run seed and empty state

- **Status:** Open
- **Description:** On first launch when the data store contains no budgets, seed a single Budget (entity) so the user is not dropped into an empty app. Aligns with empty-state expectations for the **Budgets screen**.
- **Acceptance Criteria:**
  - After first launch with an empty store, **Budgets screen** shows at least one Budget (entity) without manual creation.
  - Seeded Budget: **Name** `"Food"`; **Time Period** daily; **Allocation** `25`; **Currency** — same default as F-2.03 (locale, else USD); **Over/Under reset cadence** weekly (per [main-prd.md §6.7](main-prd.md#67-overunder-carryover-behavior)); other fields use the same defaults as F-2.03 where applicable.
  - Seeding runs **once** (first install / empty store only); deleting all budgets later does not auto-reseed.
- **Edge Cases / Notes:** None
- **Dependencies:** F-1.02, F-2.01, F-2.03

---

### T-3: Internationalization and Accessibility

#### Features

##### F-3.01: Dynamic Type

- **Status:** Open
- **Description: Dynamic Type is supported** 
- **Acceptance Criteria: None**
- **Edge Cases / Notes:** None
- **Dependencies:** None

##### F-3.02: VoiceOver

- **Status:** Open
- **Description: VoiceOver is supported**
- **Acceptance Criteria:**
  - All necessary UI elements have accessibility labels to support VoiceOver.
- **Edge Cases / Notes:** None
- **Dependencies:** F-3.03

##### F-3.03: Internationalization of text

- **Status:** Open
- **Description: VoiceOver is supported**
- **Acceptance Criteria:** 
  - All Apple-supported languages have translations for all labels.
  - All labels change automatically to match the device's locale.
- **Edge Cases / Notes:** None
- **Dependencies:** None

##### F-3.04: Internationalization of currency

- **Status:** Open
- **Description:** Currency is **per Budget** (entity) — see **Add/Edit Budget screen** (F-2.03) — not a single global app default. This feature covers formatting, symbols, and the currency catalog used when choosing a Budget’s currency.
- **Acceptance Criteria:** 
  - **Add/Edit Budget screen** includes a currency picker; all supported currency codes are available there (not on **Settings screen** as a global override).
  - Amounts and symbols in the UI respect **each Budget’s** selected currency and the user’s locale formatting rules.
  - Currency catalog (codes, symbols, localized names) is stored outside source code (e.g. YAML or equivalent).
  - The display name of each currency in the picker is internationalized.
- **Edge Cases / Notes:** None
- **Dependencies:** F-2.03, F-3.03

##### F-3.05: Dark Mode

- **Status:** Open
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

- **Status:** Open
- **Description:** Choose start day of week for weekly Budgets.
- **Acceptance Criteria:**
  - Default value is determined by locale's official week starting day. For example, Sunday in the USA, Monday in most of Europe. 
  - Configurable to be different. Will cascade to all existing Budgets. 
  - Display pop-up to acknowledge that existing Budgets will be affected.
- **Edge Cases / Notes:**
- **Dependencies:**


---

### T-6: Miscellaneous

#### Features

##### F-6.01: Allow manually adding funds

- **Status:** Open
- **Description:** User can add a transaction where the amount adds to available funds instead of subtract from it. 
- **Acceptance Criteria:**
- **Edge Cases / Notes:**
- **Dependencies:**

##### F-6.02: Expense Type on Expense Items

- **Status:** Open
- **Description:** 
  - On each Expense Item, allow user to specify an Expense Type.  
  - User can select from "Cash", "Credit Card", "Debit Card", but can also choose to type in their own value.
  - If user types in own value, that is stored as a predefined value in the future.
- **Acceptance Criteria:**
- **Edge Cases / Notes:**
- **Dependencies:**
