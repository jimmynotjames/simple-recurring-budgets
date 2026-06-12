# Delta: add-edit-expense-screen (recents-rework-spec-sync)

## REMOVED Requirements

### Requirement: Add Expense surfaces a Recents section above the Amount card (F-7.04)

**Reason**: Superseded — the Recents section moved below the Description card so the description-as-filter reads as a standard input-above/suggestions-below autocomplete, and the Amount card reclaims the top slot for the amount-first quick-log flow. Replaced by "Add Expense surfaces a Recents section below the Description card (F-7.04)".
**Migration**: None — visibility gating (Add-mode-only, true-empty absent) carries over unchanged into the replacement requirement.

### Requirement: Recents algorithm sorts by recency and dedupes by description

**Reason**: Superseded — the algorithm now builds a larger search corpus with recurrence-gated amount variants instead of pure name-dedup with a single display-sized cap. Replaced by "Recents algorithm builds a recency-ordered corpus with recurrence-gated amount variants".
**Migration**: None — exclusions (Add Funds, unnamed), folding semantics, recency ordering, and sheet-open memoization carry over unchanged into the replacement requirement.

### Requirement: Tapping a Recents tile fills name + amount and resets Add Funds

**Reason**: Superseded — the tap now applies an amount-provenance rule (user-typed amounts survive) instead of writing the amount unconditionally. Replaced by "Tapping a Recents tile applies the amount-provenance smart-apply rule" and "Double-tap (or VoiceOver custom action) performs a full replace".
**Migration**: None — name fill, Add Funds reset, no-save, and no-date-change semantics carry over unchanged into the replacement requirements.

## ADDED Requirements

### Requirement: Add Expense surfaces a Recents section below the Description card (F-7.04)

In Add mode, the Add/Edit Expense screen SHALL render a "Recents" section **directly below the Description card** (card order: Amount, Description, Recents, When, Add Funds) when the bound budget has at least one prior expense item eligible to surface as a suggestion. The placement is deliberate: the Description field doubles as the Recents filter query, so the suggestions sit directly beneath their input (input-above/suggestions-below autocomplete idiom), while the Amount card keeps the top slot for the amount-first quick-log flow. In Edit mode, the section SHALL NOT render. When the bound budget has zero eligible candidates, the section SHALL NOT render at sheet-open and SHALL NOT later appear during the sheet's lifetime.

#### Scenario: Add mode with prior expenses shows the Recents section below Description

- **WHEN** the user opens the Add Expense sheet for a budget that has at least one prior named, non-Add-Funds expense item
- **THEN** the screen renders a card titled "Recents" directly below the Description card and above the When card
- **AND** the card contains a horizontal scroll row of tappable tiles, one per candidate
- **AND** the Amount card is the topmost card in the scroll view

#### Scenario: Add mode with no prior expenses hides the section

- **WHEN** the user opens the Add Expense sheet for a budget with no prior expense items (a brand-new budget)
- **THEN** the screen does not render the Recents card
- **AND** the form opens with the Amount card at the top of the scroll view

#### Scenario: Edit mode never shows the Recents section

- **WHEN** the user opens the Edit Expense sheet for an existing expense
- **THEN** the screen does not render the Recents card

### Requirement: Recents algorithm builds a recency-ordered corpus with recurrence-gated amount variants

The Recents candidate set SHALL be a memoized **search corpus** derived from `Budget.expenseItems` at sheet-open (recomputing per keystroke is forbidden) by:

1. Excluding Add Funds entries (`ExpenseItem.isAddFunds == true`) — they are not reusable as expense suggestions.
2. Excluding entries with no description (nil or whitespace-only `name`) — they are not actionable as suggestions, and description-optional quick logging would otherwise flood the row with bare amounts.
3. Aggregating the remaining entries into (name, amount) pairs, where the name component uses a case- AND diacritic-insensitive comparison after trimming whitespace (so "Café" / "cafe" / "CAFÉ" belong to one name), and the recurrence count of a pair aggregates across that folded equivalence class.
4. Surfacing, per unique name:
   - a **base tile** — the pair with the most recent occurrence, regardless of its recurrence count (the most recent occurrence's trimmed display name and amount ride along), and
   - **variant tiles** — other pairs of the same name whose exact (name, amount) recurrence count is at least `variantRecurrenceThreshold` (3), ordered by pair recency descending and capped at `maxVariantsPerName` (2) extras per name. Pairs below the threshold SHALL NOT surface as variants, so one-off price jitter collapses to the base tile alone.
5. Ordering name groups by their most recent occurrence descending and flattening with each group's variants clustered immediately after their base tile (duplicate names read as one family; tiles never interleave across names by raw date).
6. Capping the corpus at `recentsCorpusLimit` (200).

The constants `recentsDisplayLimit` (30), `recentsCorpusLimit` (200), `variantRecurrenceThreshold` (3), and `maxVariantsPerName` (2) are deliberate product decisions pinned by unit test; changing any of them SHALL be treated as a spec-level change.

#### Scenario: Most recent occurrence per unique description is the base tile

- **WHEN** the user opens Add Expense for a budget that has logged "Coffee" at $5.50 once last week and "Coffee" at $6.00 once yesterday
- **THEN** the Recents section shows one "Coffee" tile showing $6.00 (the most recent occurrence's amount); the older singleton pair earns no variant tile

#### Scenario: A recurring second amount earns a variant tile

- **WHEN** the budget history holds "Coffee" at $5.75 once (most recent) and "Coffee" at $4.50 three times
- **THEN** the Recents section shows two "Coffee" tiles — $5.75 (base) then $4.50 (variant) — clustered adjacently

#### Scenario: Price jitter does not earn variant tiles

- **WHEN** the budget history holds "Groceries" at three different one-off amounts
- **THEN** the Recents section shows exactly one "Groceries" tile carrying the most recent amount

#### Scenario: Variant tiles are capped per name by pair recency

- **WHEN** a name has a base pair plus three other pairs that each meet the recurrence threshold
- **THEN** only the two most recently used variant pairs surface, for a maximum of three tiles under that name

#### Scenario: Add Funds entries are excluded from the candidate set

- **WHEN** the user opens Add Expense for a budget whose history includes both expense entries and Add Funds entries
- **THEN** the Recents section only surfaces the expense entries

#### Scenario: Unnamed entries are excluded from the candidate set

- **WHEN** the user opens Add Expense for a budget whose history includes some expenses with no description
- **THEN** the Recents section only surfaces the named expenses

#### Scenario: Corpus is capped at the corpus limit, not the display limit

- **WHEN** the user opens Add Expense for a budget with more eligible tiles than `recentsCorpusLimit`
- **THEN** the memoized corpus holds at most `recentsCorpusLimit` tiles, ordered per the grouping rules above

### Requirement: Recents display caps the row at the display limit while the filter searches the full corpus

The rendered Recents row SHALL show at most `recentsDisplayLimit` (30) tiles in both query states: with an empty Description query, the first `recentsDisplayLimit` tiles of the corpus; with a non-empty query, the first `recentsDisplayLimit` matching tiles. The typed-query filter SHALL match against the **entire memoized corpus**, not the rendered row, so a name outside the visible row still surfaces once the query narrows the matches.

#### Scenario: Unfiltered row is capped at the display limit

- **WHEN** the corpus holds more than `recentsDisplayLimit` tiles and the Description query is empty
- **THEN** the row renders exactly `recentsDisplayLimit` tiles, most recent name-groups first

#### Scenario: Typing surfaces a name beyond the visible row

- **WHEN** an eligible name's tile falls outside the rendered row because more recent tiles fill the display cap
- **AND** the user types a substring of that name into the Description field
- **THEN** the matching tile appears in the filtered row

### Requirement: Tapping a Recents tile applies the amount-provenance smart-apply rule

The draft's amount SHALL carry a provenance classification: **empty** (no amount; initial state or after the user clears/deletes it), **user-typed** (the user entered or edited the current amount this session), or **tile-seeded** (a Recents apply wrote the current amount). Echo writes — the amount field re-parsing the text it re-seeded after an external write — SHALL NOT change provenance.

A single tap on a Recents tile SHALL always write the suggestion's `name` to the draft and SHALL reset the Add Funds toggle (`isAddFunds`) to off (a Recents tile represents a prior *expense*). The tap SHALL write the suggestion's `amount` **only when the draft amount's provenance is empty or tile-seeded**; a user-typed amount SHALL survive the tap, and SHALL keep surviving across subsequent single taps (suggestion-switching never clobbers typed input). An amount written by a tap is classified tile-seeded, so a later single tap on a different tile replaces it. The tap SHALL NOT persist the expense — the user remains on the sheet to review and confirm via Save — and SHALL NOT alter the `date` field or other draft state.

Rationale: a user-typed amount is fresher intent than the tile's historical amount, and the silent-overwrite failure (a wrong amount saved unnoticed) is costlier than the visible not-applied failure (fixable in place). The escape hatches for explicitly wanting the tile's amount over a typed one are the amount clear button followed by a re-tap, or the double-tap full replace.

#### Scenario: Tap with an empty amount fills name and amount but does not save

- **WHEN** the draft amount is empty and the user taps a Recents tile labeled "Coffee · $5.50"
- **THEN** the Description field shows "Coffee"
- **AND** the Amount field shows $5.50
- **AND** the user remains on the Add Expense sheet
- **AND** no `ExpenseItem` is persisted

#### Scenario: Tap preserves a user-typed amount

- **WHEN** the user has typed $12.80 into the Amount field, then taps a Recents tile labeled "Coffee · $5.50"
- **THEN** the Description field shows "Coffee"
- **AND** the Amount field still shows $12.80

#### Scenario: A second tap replaces a tile-seeded amount

- **WHEN** the draft amount was filled by a prior Recents tap and the user taps a different tile
- **THEN** both the name and the amount update to the newly tapped suggestion

#### Scenario: Clearing the amount re-arms filling

- **WHEN** the user typed an amount, then cleared it (✕ or delete-all), then taps a Recents tile
- **THEN** the tile's amount fills the Amount field

#### Scenario: Tap resets the Add Funds toggle to off

- **WHEN** the user has the Add Funds toggle on, then taps a Recents tile
- **THEN** the Add Funds toggle becomes off
- **AND** the draft's `name` is set from the tapped suggestion (and `amount` per the provenance rule)

### Requirement: Double-tap (or VoiceOver custom action) performs a full replace overriding provenance

A double-tap on a Recents tile SHALL write **both** `name` and `amount` from the suggestion unconditionally — overriding the amount-provenance rule — and SHALL reset Add Funds, classifying the written amount tile-seeded (a later single tap on another tile may replace it). The double-tap SHALL be recognized via a simultaneous gesture so that single taps incur no recognition delay; consequently the double-tap's first tap runs the normal smart apply before the second tap upgrades it to the full replace (the end state is the full replace). VoiceOver users SHALL have an equivalent custom action (named with the localized equivalent of "Replace amount and description"), because VoiceOver's double-tap gesture is its activation gesture. The full replace SHALL NOT emit a second `expense_recent_reused` analytics event (the pair's first tap already emitted one).

#### Scenario: Double-tap overrides a user-typed amount

- **WHEN** the user has typed $12.80 into the Amount field, then double-taps a Recents tile labeled "Coffee · $5.50"
- **THEN** the Description field shows "Coffee" and the Amount field shows $5.50

#### Scenario: Single taps are not delayed by double-tap recognition

- **WHEN** the user single-taps a Recents tile
- **THEN** the smart apply happens immediately, without waiting for a possible second tap

#### Scenario: VoiceOver custom action performs the full replace

- **WHEN** a VoiceOver user invokes the "Replace amount and description" custom action on a Recents tile while a user-typed amount is present
- **THEN** both fields are replaced from the suggestion, same as the sighted double-tap

## MODIFIED Requirements

### Requirement: Recents section filters as the user types into Description

The Recents candidate corpus SHALL filter in place as the user types into the Description field, using a case- AND diacritic-insensitive substring match against each candidate's name. The match SHALL run against the **full memoized corpus** (not the rendered row), and the filtered result SHALL render capped at `recentsDisplayLimit`. The section SHALL stay on the same surface as the form — no separate picker view, sheet, or screen is presented. The corpus SHALL NOT be recomputed per keystroke. Clearing the Description field (including via its trailing clear button) SHALL restore the unfiltered row.

#### Scenario: Typing into Description narrows the Recents row

- **WHEN** the user opens Add Expense and the Recents section shows tiles for "Coffee", "Lunch", and "Groceries"
- **AND** the user types "co" into the Description field
- **THEN** the Recents row shows only the "Coffee" tile (substring match)

#### Scenario: Filter is case-insensitive

- **WHEN** the Recents section contains a "Coffee" tile
- **AND** the user types "COFFEE" into the Description field
- **THEN** the "Coffee" tile remains visible

#### Scenario: Filter is diacritic-insensitive

- **WHEN** the Recents section contains a "Café" tile
- **AND** the user types "cafe" into the Description field
- **THEN** the "Café" tile remains visible
- **AND** the same equivalence groups the corpus, so the user never sees "Café" and "cafe" as separate base tiles

#### Scenario: Clearing the Description restores the full row

- **WHEN** the user has typed a query that narrows the Recents row
- **AND** the user taps the Description field's trailing clear button
- **THEN** the Recents row returns to its unfiltered display-capped state

### Requirement: Recents surface is accessible to VoiceOver and Dynamic Type users

Each tappable Recents tile SHALL expose a composed `accessibilityLabel` that announces both the description and the formatted amount, an `accessibilityHint` that explains the tap action ("Fills the amount and description for review."), and a custom accessibility action (localized equivalent of "Replace amount and description") mirroring the sighted double-tap full replace. The trailing swipe-affordance icon (when shown) SHALL be hidden from VoiceOver (`accessibilityHidden(true)`) because its meaning is reproduced by VoiceOver's natural scroll-container behavior. The "No matches" placeholder SHALL expose an `accessibilityLabel` distinct from the visible glyph (e.g., "No matching recent expenses"). The phantom-content sizing anchor used by the placeholder SHALL be hidden from VoiceOver.

Tile geometry — the maximum tile width and the inner padding values — SHALL scale with Dynamic Type via `@ScaledMetric(relativeTo: .subheadline)` so the section remains legible at larger type sizes.

#### Scenario: VoiceOver reads a Recents tile as one combined element

- **WHEN** a VoiceOver user focuses a Recents tile labeled visually as "Coffee · $5.50"
- **THEN** VoiceOver announces a single combined label including both the name and the formatted amount
- **AND** announces the hint that explains the tap fills the draft for review

#### Scenario: VoiceOver exposes the full-replace custom action

- **WHEN** a VoiceOver user focuses a Recents tile
- **THEN** the actions rotor offers "Replace amount and description"

#### Scenario: Decorative swipe icon is silent to VoiceOver

- **WHEN** the Recents row contains the trailing swipe-affordance icon
- **THEN** VoiceOver does not announce the icon as a separate element

#### Scenario: Tile geometry scales with larger Dynamic Type sizes

- **WHEN** the user has set Dynamic Type to a larger size (e.g., `xxxLarge`)
- **THEN** the Recents tile maximum width and padding grow proportionally relative to the subheadline text style

### Requirement: Recents UI strings are keyed in Localizable.xcstrings

All user-facing strings introduced by the Recents surface SHALL be registered in `Localizable.xcstrings` under the `addEditExpense.recents.*` namespace, with translator-friendly `comment:` text describing the surface, context, and any interpolated arguments. The keys SHALL be translated to every App Store storefront locale listed in `docs/main-prd.md` §6.8.3 (F-3.03) via the `translate-new-strings` skill before the change ships.

The keys SHALL include at minimum: the section title, the "No matches" placeholder copy, each accessibility label and hint introduced by the accessibility requirement, and the full-replace custom action name (`addEditExpense.recents.tile.accessibilityAction.fullReplace`).

#### Scenario: All visible Recents strings have localization keys

- **WHEN** an auditor inspects the Recents surface source
- **THEN** no bare-literal `Text("…")` calls appear on user-visible strings under the `addEditExpense.recents.*` surface
- **AND** every string is a `String(localized:defaultValue:comment:)` call (or equivalent) under the `addEditExpense.recents.*` namespace

#### Scenario: Translations exist for every storefront locale

- **WHEN** `python scripts/translate_catalog/check_translations.py` runs after the Recents work lands
- **THEN** the check passes with no missing or stale translations for any `addEditExpense.recents.*` key

### Requirement: Recents tile tap emits a Mixpanel `expense_recent_reused` event (F-8.02)

When the user taps a Recents tile, the app SHALL emit an `expense_recent_reused` analytics event via the injected `AnalyticsClient`. The event SHALL contain only categorical, non-PII properties per the analytics-spec.md §2.1 no-PII rule. The event SHALL include at minimum:

- The bound budget's period (`period`).
- A bucketed count of the number of Recents tiles visible when the tap happened (`recents_visible_count`); the top bucket is `8+` (open-ended, since the display cap exceeds 15).
- A bucketed position of the tapped tile in the visible row (`recents_tap_position`).
- A bucketed length of the typed Description query at tap time (`name_query_length`).

The event SHALL NOT include the description string, the amount value, or any user-identifying signal. Emission SHALL be subject to the user's consent state per analytics-spec.md §2.1 (same gating as `expense_logged` and `expense_edited`). Exactly one event SHALL fire per physical interaction: the double-tap full replace does not emit a second event (its first tap already emitted one), and the event fires regardless of whether the amount was filled or preserved by the provenance rule.

#### Scenario: Tap emits the analytics event with categorical properties

- **WHEN** the user taps a Recents tile in Add Expense on a daily budget
- **AND** the user has consented to analytics
- **THEN** the app emits an `expense_recent_reused` event
- **AND** the event includes `period: "daily"` (or its analytics-mapped equivalent)
- **AND** the event includes bucketed values for `recents_visible_count`, `recents_tap_position`, and `name_query_length`
- **AND** the event does not include the description string, the amount value, or any user identifier

#### Scenario: Tap does not emit when analytics consent is withheld

- **WHEN** the user has withheld analytics consent (or is in a consent-required jurisdiction without granting consent)
- **AND** the user taps a Recents tile
- **THEN** the app does not emit the `expense_recent_reused` event
- **AND** the draft fields are still populated (the analytics gate does not block the feature)

#### Scenario: Double-tap emits exactly one event

- **WHEN** the user double-taps a Recents tile with analytics consent granted
- **THEN** exactly one `expense_recent_reused` event is emitted (from the pair's first tap)

### Requirement: Form fields are Amount, Description (optional), and When (date/time)

The Add/Edit/View Expense screen SHALL collect exactly three user-editable fields, organised into three cards (Amount, Description, When) per the user-approved layout. Fields SHALL always be directly editable in place — there SHALL NOT be any "edit mode" toggle that switches between read-only and editable states (per F-2.04 AC).

The fields are:

- **Amount** (`Decimal?` in `AddEditExpenseViewModel`) — entered via a **`DecimalInputField`** — a `UITextField`-backed `UIViewRepresentable` — rather than SwiftUI's `TextField(value:format:)` (which rejects keystrokes whenever parsing throws, breaking RTL / non-Western-digit entry) or `TextField(text:)` + `.onChange` (which on iOS 17+ fails to render typed text until the field resigns first responder). The field is **seeded** from the draft `Decimal?` via `OptionalDecimalFormatStyle.editableText(_:)` at the expense currency's minor-unit precision (e.g. 0 for JPY, 2 for USD, 3 for BHD/KWD; no grouping separators), and an empty field maps to `nil` (blank default in Add mode). Each edit is parsed back to `Decimal?` via the style's **locale-aware `parseStrategy`**, which accepts whatever numbering system the locale's keyboard emits (Western, Arabic-Indic, Devanagari, …). Entry is **capped live** to the currency's minor-unit count by the field's delegate: 0-decimal currencies (JPY, KRW, …) reject the decimal separator entirely (no fractional entry), and other currencies accept at most that many fraction digits. Placeholder `"0"` (key `addEditExpense.field.amount.placeholder`). Keyboard type SHALL be `.decimalPad`. A currency symbol/code SHALL be displayed adjacent to the field in the same `HStack`, on the **locale-correct side** (leading or trailing); the decoration is derived from `settings.currencyDisplay.affixes(for: viewModel.currencyCode)` — which returns `(leading, trailing)` strings whose placement and spacing follow the same currency `FormatStyle` used by `Decimal.formatted(currencyCode:display:locale:)` (e.g. leading `"$"` for USD in en_US, trailing `" €"` for EUR in fr_FR), mirroring correctly in RTL — and SHALL update reactively whenever `settings.currencyDisplay` changes. The decoration `Text`(s) SHALL be `accessibilityHidden`. Accessibility label `"Expense amount"` (key `addEditExpense.field.amount.accessibilityLabel`). The view SHALL read `AppSettings` via `@Environment(AppSettings.self)`; the VM SHALL NOT store `AppSettings`.
- **Description** (`String` in the VM, persisted as `String?`) — bound to a single-line `TextField` in the Description card. Placeholder `"e.g. Coffee"` (key `addEditExpense.field.name.placeholder`). Section label `"Description (optional)"` (key `addEditExpense.section.name`). Accessibility label `"Expense description"` (key `addEditExpense.field.name.accessibilityLabel`). Per F-2.04 AC, the description is optional — Save SHALL NOT be gated on it being non-empty. When the field is non-empty, a trailing clear button (`xmark.circle.fill`, mirroring `CurrencyAmountField`'s pattern) SHALL render inside the card and clear the field on tap; its accessibility label is "Clear description" (key `addEditExpense.field.name.clearButton.accessibilityLabel`). Clearing also restores the unfiltered Recents row (the Description doubles as the Recents filter query per F-7.04).
- **When** (`Date`) — bound to a `DatePicker` with `displayedComponents: [.date, .hourAndMinute]` and `.datePickerStyle(.compact)`. Section label `"When"` (key `addEditExpense.section.when`). The picker's own label is hidden (`.labelsHidden()`) and provided via the section header.

Section labels for the three cards use keys `addEditExpense.section.amount`, `addEditExpense.section.name`, and `addEditExpense.section.when`.

The currency code shown in the Amount decoration SHALL be derived as follows:

- In Add mode, from the in-flight `Budget.currencyCode`.
- In Edit/View mode, from `expense.budget?.currencyCode`, falling back to `Locale.current.currency?.identifier ?? "USD"` if the parent budget reference is `nil` (defensive against orphan rows synced from another device).

The currency code SHALL be stored on the VM as a `let` (immutable for the lifetime of the sheet); the user CANNOT change the per-expense currency from this screen.

#### Scenario: All three fields render in their cards

- **WHEN** the sheet is visible in either Add or Edit/View mode
- **THEN** the screen displays three cards in this order: Amount, Description, When; the Amount card contains the currency decoration and the numeric field; the Description card contains the single-line text field; the When card contains the compact date/time picker

#### Scenario: Amount currency decoration matches AppSettings.currencyDisplay on the locale-correct side

- **WHEN** `settings.currencyDisplay == .symbol`, the budget's currency is `"USD"`, and the locale is `en_US`
- **THEN** the Amount card displays `"$"` as a **leading** decoration before the numeric field, and no trailing decoration

- **WHEN** `settings.currencyDisplay == .symbol`, the budget's currency is `"EUR"`, and the locale is `fr_FR`
- **THEN** the Amount card displays the `"€"` symbol as a **trailing** decoration after the numeric field, and no leading decoration

- **WHEN** `settings.currencyDisplay == .code` and the budget's currency is `"USD"`
- **THEN** the Amount card displays `"USD"` as a leading decoration

- **WHEN** `settings.currencyDisplay == .codeAndSymbol` and the budget's currency is `"USD"`
- **THEN** the Amount card displays `"USD $"` as a leading decoration

#### Scenario: Currency decoration updates live when settings change

- **WHEN** the user changes `AppSettings.currencyDisplay` while the sheet is open
- **THEN** the decoration around the Amount field updates immediately to reflect the new preference without dismissing or reloading the sheet

#### Scenario: Amount fraction precision follows the budget currency

- **WHEN** the budget's currency is a 3-decimal currency (e.g. `"BHD"`) and an existing amount of `1.234` is shown
- **THEN** the field displays all three fraction digits (`1.234`), not a value truncated to two places

- **WHEN** the budget's currency is a 0-decimal currency (e.g. `"JPY"`)
- **THEN** the field renders the amount with no fraction digits, AND tapping the decimal-separator key during entry has no effect (fractional input is not possible)

#### Scenario: Amount field parses optional Decimal with locale-aware parsing

- **WHEN** the user clears the Amount `TextField` or leaves it empty in Add mode
- **THEN** the draft `amount` is `nil` (blank), not `0`

- **WHEN** the user enters a number in the Amount `TextField`
- **THEN** the parse strategy reads the text using a locale-aware `Decimal.FormatStyle`, so locale-appropriate decimal/grouping separators apply; successful parse yields `Decimal`; the underlying VM state remains `Decimal?` (entered value or `nil` when empty)

- **WHEN** the user enters an unparseable string (e.g. via paste)
- **THEN** the parse strategy throws a `CocoaError` and the field rejects the input

#### Scenario: Amount field accepts non-Western numerals

- **WHEN** the locale's `.decimalPad` emits non-Western digits (e.g. Arabic-Indic `٠١٢٣…` in `ar_EG`/`ar_SA`, Extended Arabic-Indic in `fa_IR`, or Devanagari in `ne_NP`) and the user taps digits into the Amount field
- **THEN** the digits SHALL be accepted and parsed to the corresponding `Decimal` (the field SHALL NOT reject the keystrokes), because parsing routes through the locale-aware `Decimal.FormatStyle` rather than `Decimal(string:locale:)`

#### Scenario: Description field accepts arbitrary text including empty

- **WHEN** the user types nothing in the Description field
- **THEN** the draft `name` remains the empty string, the persisted value (on Save) is `nil`, and Save is NOT gated on the field

- **WHEN** the user types `"   Coffee   "` in the Description field
- **THEN** the draft `name` is the literal user-entered string `"   Coffee   "`, but on Save the persisted `ExpenseItem.name` is the trimmed value `"Coffee"`

- **WHEN** the user types only whitespace in the Description field
- **THEN** on Save the persisted `ExpenseItem.name` is `nil` (whitespace-only collapses to no description)

#### Scenario: Description clear button clears the field

- **WHEN** the Description field contains text
- **THEN** a trailing clear button is visible inside the Description card

- **WHEN** the user taps the clear button
- **THEN** the draft `name` becomes the empty string
- **AND** in Add mode the Recents row (when present) returns to its unfiltered state

- **WHEN** the Description field is empty
- **THEN** no clear button renders

#### Scenario: When field defaults to current date and time in Add mode

- **WHEN** the sheet opens in Add mode
- **THEN** the When picker is initialised to `Date()` (current wall-clock time at sheet construction) and is freely editable by the user

#### Scenario: When field is seeded from the existing expense in Edit mode

- **WHEN** the sheet opens in Edit/View mode for an existing `ExpenseItem`
- **THEN** the When picker is initialised to `expense.date`, with date and time components both reflecting the stored value
