# Localization and VoiceOver Audit

| Field                | Value                                |
| -------------------- | ------------------------------------ |
| **Date**             | 2026-04-30                           |
| **Author / Owner**   | Jimmy Ho (with agentic assistance)   |
| **Scope**            | Every user-facing surface in `simple-recurring-budgets/` |
| **Catalog**          | [`simple-recurring-budgets/Resources/Localizable.xcstrings`](../../simple-recurring-budgets/Resources/Localizable.xcstrings) |
| **Workflow**         | Standalone audit (not OpenSpec) — explicit user-chosen exception to the repo default. |
| **Type**             | Audit + full inline remediation (single effort) |
| **Languages**        | English source + pseudo-localization smoke (no real translations introduced) |

> Companion implementation: code changes referenced in the **Remediation** section land in the same effort as this report. After remediation, the **Verification** appendix records pass/fail per screen.

## Method

### Pass A — Localization

1. **String inventory.** Ripgrep over `simple-recurring-budgets/` for every UI-facing string surface (`Text`, `Button`, `Label`, `navigationTitle`, `Menu`, `Toggle`, `Picker`, `Section`, `confirmationDialog`, `alert`, `TextField`, `searchable`, `Text(verbatim:)`, plus accessibility strings) and a comparison against the catalog (`String(localized:)`, `LocalizedStringKey`, `NSLocalizedString`).
2. **Catalog audit.** Scan [`Localizable.xcstrings`](../../simple-recurring-budgets/Resources/Localizable.xcstrings) for empty/orphaned entries, missing translator `comment:`, naming-convention drift, and absent keys.
3. **Pseudo-localization smoke procedure.** A repeatable smoke (no shared-scheme mutation) is documented under **Appendix B**.

### Pass B — VoiceOver

1. **Static checklist** applied per file under `Views/`:
   - Every interactive control has a meaningful label (no system-name fallback such as "plus.circle.fill").
   - Custom composite views (`RemainingBar`, `CarryOverChip`) collapse to a single accessibility element with a coherent label.
   - Decorative imagery is hidden from assistive tech.
   - Destructive actions carry a hint describing irreversibility.
   - Headings / titles use `.accessibilityAddTraits(.isHeader)` for rotor navigation.
   - Financial amounts include currency context.
   - Focus order matches reading order.
   - `swipeActions` are exposed via an explicit `accessibilityAction` (since SwiftUI does **not** auto-expose them to VoiceOver in the same way it does standard list deletes).
2. **Live walkthrough procedure** is documented under **Appendix C**; the live pass is recorded in the **Verification** appendix.

## Severity scale

| Level    | Meaning                                                                                              |
| -------- | ---------------------------------------------------------------------------------------------------- |
| BLOCKER  | Ship-blocker; user-facing English literal, fully missing label, or destructive action hidden from VO. |
| HIGH     | Visible-to-user defect; spec deviation; control not VO-discoverable.                                  |
| MEDIUM   | Rotor / structural a11y gap; suboptimal element grouping; copy hygiene.                               |
| LOW      | Polish / lint; comment hygiene; orphan key cleanup.                                                   |

---

## Section 1 — Localization findings

### Summary

| ID    | Severity | Screen / Surface                                                              | Finding                                                                                                   |
| ----- | -------- | ----------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| L-01  | BLOCKER  | `BudgetDetailView` reset-budget confirmation dialog                            | `Button("Cancel", role: .cancel) {}` is a hard-coded English literal (line 152).                          |
| L-02  | BLOCKER  | `BudgetDetailView` reset-carry-over alert                                     | `Button("Cancel", role: .cancel) {}` is a hard-coded English literal (line 177).                          |
| L-03  | LOW      | `Localizable.xcstrings`                                                       | Empty key `"Cancel"` (no value, no comment) auto-extracted from L-01/L-02. Orphan to remove.              |
| L-04  | HIGH     | `SettingsView` — Currency Display picker                                       | Picker rows render only the locale-aware example. Spec F-2.05 requires `"<option label> — <example>"`. The localized `option.label` is never displayed. |
| L-05  | MEDIUM   | `SettingsView` — version row                                                  | `Text("\(appVersion) (\(buildNumber))")` auto-extracts to opaque key `"%@ (%@)"` with no project-namespaced key. Not translator-friendly. |
| L-06  | LOW      | `CurrencyPickerView` — Cancel toolbar button                                  | Reuses `addEditBudget.action.cancel` whose `comment:` mentions only the Add/Edit Budget sheet. Misleading for translators. Either retarget the comment or introduce a shared `common.action.cancel`. |

### Screens — full check

#### S-L1: `BudgetsView` ([`BudgetsView.swift`](../../simple-recurring-budgets/Views/BudgetsView.swift))

| Line | Surface                                                        | Status |
| ---- | -------------------------------------------------------------- | ------ |
| 19   | `navigationTitle("budgets.navigationTitle")`                   | OK     |
| 30–43| Settings toolbar Label + accessibilityHint                     | OK     |
| 51–66| Add-budget toolbar Image + label + hint                        | OK     |
| 73–101 | Empty-state title / description / CTA                        | OK     |
| 187  | `Text(budget.name)` — user data (verbatim)                     | OK     |
| 196  | `Text(remaining.formatted(...))` — formatted currency          | OK     |
| 202  | `Text(period.listLabel)`                                       | OK (delegated to `BudgetPeriod+Display.swift`) |
| 217–294 | All accessibility labels / hints                            | OK     |

#### S-L2: `BudgetDetailView` ([`BudgetDetailView.swift`](../../simple-recurring-budgets/Views/BudgetDetailView.swift))

| Line | Surface                                                        | Status                  |
| ---- | -------------------------------------------------------------- | ----------------------- |
| 66–92  | Add Expense primary button / a11y label / hint               | OK                      |
| 100  | `navigationTitle(budget.name)` — user data                     | OK                      |
| 105–134 | Edit Budget / Reset Budget menu items                        | OK                      |
| 137–158 | Reset Budget confirmation dialog                             | **BLOCKER L-01** at line 152 (`Button("Cancel", role: .cancel) {}`) |
| 162–184 | Reset Carry-Over alert                                       | **BLOCKER L-02** at line 177 (`Button("Cancel", role: .cancel) {}`) |
| 203–211 | Header amount + period label                                 | OK                      |
| 228–239 | Reset button + a11y label                                    | OK                      |
| 282–290 | Header a11y labels (over-budget and on-budget)              | OK                      |

#### S-L3: `BudgetDetailView+ExpenseSection` ([`BudgetDetailView+ExpenseSection.swift`](../../simple-recurring-budgets/Views/BudgetDetailView+ExpenseSection.swift))

| Line | Surface                                                        | Status |
| ---- | -------------------------------------------------------------- | ------ |
| 11–22 | `budgetDetail.empty.noExpenses`                                | OK    |
| 41–46 | Section header HStack (title + total amount)                   | Localized title OK; total is `Decimal.formatted(...)` — locale-aware OK |
| 70–77 | Swipe action label                                             | OK    |
| 105–161 | Per-period section titles (current / past)                   | OK    |
| 163–190 | Per-period current empty captions                            | OK    |
| 232    | `budgetDetail.expenseRow.unnamed` placeholder                 | OK    |
| 251–259 | Expense row a11y labels (standard + add-funds)               | OK    |

#### S-L4: `AddEditBudgetView` ([`AddEditBudgetView.swift`](../../simple-recurring-budgets/Views/AddEditBudgetView.swift))

| Line | Surface                                                        | Status |
| ---- | -------------------------------------------------------------- | ------ |
| 35–46 | navigationTitle add/edit                                       | OK    |
| 51–71 | Cancel / Save toolbar                                          | OK    |
| 78–125 | Delete confirmation dialog and Delete button label/hint        | OK    |
| 132–155 | Name field (placeholder + a11y)                               | OK    |
| 161–217 | Allocation field + currency pill                              | OK    |
| 222–235 | Period section + chips                                         | OK    |
| 240–272 | Carry-over toggle + caption                                    | OK    |

#### S-L5: `AddEditExpenseView` ([`AddEditExpenseView.swift`](../../simple-recurring-budgets/Views/AddEditExpenseView.swift))

| Line | Surface                                                        | Status |
| ---- | -------------------------------------------------------------- | ------ |
| 121–134 | navigationTitle add/existing                                   | OK    |
| 138–161 | Cancel + Save toolbar                                          | OK    |
| 164–211 | Delete confirmation dialog and Delete button label/hint        | OK    |
| 215–246 | Amount field (placeholder + a11y)                              | OK    |
| 250–273 | Name field (placeholder + a11y)                                | OK    |
| 276–298 | When (DatePicker) — `labelsHidden()` with prior localized title | OK    |

#### S-L6: `SettingsView` ([`SettingsView.swift`](../../simple-recurring-budgets/Views/SettingsView.swift))

| Line | Surface                                                        | Status                                                            |
| ---- | -------------------------------------------------------------- | ----------------------------------------------------------------- |
| 45–61| navigationTitle, Done                                          | OK                                                                |
| 64–97| Week-start confirmation alert (title, confirm, cancel, message) | OK                                                                |
| 107–134 | Carry-over toggle + footer                                     | OK                                                                |
| 139–171 | Week-start picker + section header                             | OK (weekday names sourced from `Calendar.standaloneWeekdaySymbols`) |
| 175–196 | Currency display picker + section header                       | **HIGH L-04** — picker rows show only `option.example()`, not `option.label`. |
| 199–226 | iCloud section + footers                                       | OK                                                                |
| 229–280 | Support section (feedback / rate / privacy)                    | OK                                                                |
| 285–301 | About section + version row                                    | **MEDIUM L-05** — `Text("\(appVersion) (\(buildNumber))")` auto-extracts to opaque key. |
| 308–377 | iCloud status row (4 states)                                   | OK                                                                |

#### S-L7: `CurrencyPickerView` ([`CurrencyPickerView.swift`](../../simple-recurring-budgets/Views/CurrencyPickerView.swift))

| Line | Surface                                                        | Status                                                            |
| ---- | -------------------------------------------------------------- | ----------------------------------------------------------------- |
| 17–22| `searchable` prompt                                            | OK                                                                |
| 24–28| navigationTitle                                                | OK                                                                |
| 30–40| Cancel toolbar button                                          | **LOW L-06** — reuses `addEditBudget.action.cancel`; comment misleading. |
| 47–77| Currency row (code, localized name, checkmark) + selected a11y value | OK (display name comes from `Locale.localizedString(forCurrencyCode:)`) |

#### S-L8: `CarryOverChip` ([`CarryOverChip.swift`](../../simple-recurring-budgets/Views/CarryOverChip.swift))

| Line | Surface                                                        | Status |
| ---- | -------------------------------------------------------------- | ------ |
| 26   | `carryOver.label`                                              | OK    |
| 47–67 | Surplus / deficit / zero a11y labels                           | OK    |

#### S-L9: `BudgetPeriod+Display`, `CurrencyDisplayPreference`, `Formatters`, `OptionalDecimalFormatStyle`

All localized strings are catalog-keyed with comments. No findings.

### Catalog hygiene

- **Total keys:** 100 (validated via `localizations` count).
- **Orphan empty key:** `"Cancel"` (line 987–989) — no value, no comment. Created when literal `Button("Cancel", role: .cancel)` was first authored. Remove during remediation.
- **All other keys** carry translator-friendly `comment:` text.
- **Naming convention:** dotted, screen-prefixed (`addEditBudget.*`, `budgetDetail.*`, `settings.*`, `carryOver.*`, `period.*`, `currencyPicker.*`, `toolbar.*`, `date.*`). One exception: the auto-extracted `"%@ (%@)"` key (L-05) — not screen-prefixed.
- **No missing keys**: every `String(localized: KEY, ...)` call site corresponds to a present catalog entry (verified by sampling and by the `extractionState: extracted_with_value` flag).
- **No count-driven plurals** in the codebase — all current copy is count-free or rephrased to be count-free, consistent with `docs/tech-design-doc.md` §5.1.

---

## Section 2 — VoiceOver findings

### Summary

| ID    | Severity | Screen / Surface                                                  | Finding                                                                                                                                              |
| ----- | -------- | ----------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| V-01  | HIGH     | `BudgetDetailView+ExpenseSection` swipe-to-delete                 | `swipeActions` is **not auto-exposed** to VoiceOver. Users with VO cannot delete an expense without a custom `accessibilityAction(named:)` on the row. |
| V-02  | MEDIUM   | `BudgetDetailView+ExpenseSection` current-period section header   | Header `HStack { Text(title); Spacer(); Text(total) }` produces two VO elements; should combine to one with a coherent label like "Current Day, total $20.00". |
| V-03  | MEDIUM   | `BudgetDetailView` status header                                  | Combined element lacks `.accessibilityAddTraits(.isHeader)` — invisible to the VoiceOver headings rotor.                                              |
| V-04  | MEDIUM   | `CarryOverChip`                                                   | HStack of Image + 2 × Text never coalesces into a single VO element; `.accessibilityLabel(...)` alone does not collapse children. Add explicit `.accessibilityElement(children: .ignore)`. |
| V-05  | MEDIUM   | `BudgetsView` `BudgetRowView` carry-over chip                     | Same root cause as V-04 (chip embedded in row); the row-level addition of `.accessibilityAddTraits(.isStaticText)` does not collapse the chip into one element. |
| V-06  | LOW      | `BudgetDetailView` Reset Carry-Over button                        | Has accessibility label but no hint describing the consequence. Add hint.                                                                            |
| V-07  | LOW      | `BudgetDetailView` reset-budget menu item                         | Carries `role: .destructive` (good) but no hint explaining what gets deleted (expenses + carry-over). Add hint.                                       |
| V-08  | LOW      | `CurrencyPickerView` row                                          | HStack of code + name + checkmark exposes 2–3 separate VO elements. Combine with explicit `.accessibilityLabel("\(code), \(name ?? "")")`.            |

### Screens — full check

#### S-V1: `BudgetsView` (root list)

| Element                                  | Status                                                                 |
| ---------------------------------------- | ---------------------------------------------------------------------- |
| Settings toolbar                         | Label + hint — OK                                                      |
| EditButton                               | System control — OK                                                    |
| Add-budget toolbar                       | Label + hint — OK                                                     |
| Empty state CTA                          | OK                                                                    |
| `BudgetRowView` row button               | Label + hint, computed for over-budget — OK                            |
| `BudgetRowView` carry-over chip          | **V-05** — chip not coalesced                                          |
| `BudgetRowView` add-expense button       | Label + hint — OK                                                     |
| `RemainingBar`                           | `.accessibilityHidden(true)` — OK                                     |

#### S-V2: `BudgetDetailView`

| Element                                  | Status                                                                 |
| ---------------------------------------- | ---------------------------------------------------------------------- |
| Status header (combined element)         | Label OK; **V-03** missing `.isHeader` trait                           |
| Carry-over chip + Reset                   | **V-04** chip not coalesced; reset has label but **V-06** no hint     |
| Add Expense primary button               | Label + hint — OK                                                     |
| Toolbar overflow Menu                    | "Budget options" — OK                                                 |
| Edit Budget menu item                    | Inherits standard button traits — OK                                  |
| Reset Budget menu item                   | Destructive role; **V-07** missing hint                                |
| Reset-Budget confirmation dialog         | Title localized; cancel button **L-01** (also breaks VO localization)  |
| Reset-Carry-Over alert                   | Title localized; cancel button **L-02**                                |
| Expense rows                             | Combined element + a11y label — OK                                    |
| **Swipe-to-delete**                      | **V-01 HIGH** — no `accessibilityAction`                              |
| Current-period section header            | **V-02** — title + total are two elements                             |

#### S-V3: `AddEditBudgetView`

| Element                                  | Status                                                                 |
| ---------------------------------------- | ---------------------------------------------------------------------- |
| Cancel / Save toolbar                    | OK                                                                    |
| Name field                               | a11y label — OK                                                       |
| Allocation field                         | a11y label includes formatted amount — OK                             |
| Currency pill                            | a11y label + hint — OK                                                |
| Period chips                             | a11y label + `.isSelected` trait when active — OK                     |
| Carry-over toggle                        | Default toggle a11y + hint — OK                                       |
| Delete Budget button                     | Hint describes destruction — OK                                       |

#### S-V4: `AddEditExpenseView`

| Element                                  | Status                                                                 |
| ---------------------------------------- | ---------------------------------------------------------------------- |
| Cancel / Save toolbar                    | OK                                                                    |
| Amount field                             | a11y label — OK                                                       |
| Name field                               | a11y label — OK                                                       |
| When (DatePicker)                        | `labelsHidden()` with localized title — OK                            |
| Delete Expense button                    | Hint describes destruction — OK                                       |

#### S-V5: `SettingsView`

| Element                                  | Status                                                                 |
| ---------------------------------------- | ---------------------------------------------------------------------- |
| Done toolbar                             | OK                                                                    |
| Carry-over toggle                        | Hint — OK                                                             |
| Week Starts On picker                    | Hint — OK; weekday names are localized via Calendar                    |
| Currency Display picker                  | **L-04** — option label not rendered. (VO inherits the same defect.)   |
| iCloud status row (4 states)             | Each variant has explicit `.accessibilityLabel(...)` — OK             |
| Send Feedback link                       | Hint — OK                                                             |
| Rate the App button                      | Hint — OK                                                             |
| Privacy Policy link                      | Hint — OK                                                             |
| Version row                              | Combined element + label — OK                                         |

#### S-V6: `CurrencyPickerView`

| Element                                  | Status                                                                 |
| ---------------------------------------- | ---------------------------------------------------------------------- |
| Search field                             | Localized prompt — OK                                                 |
| Cancel toolbar                           | OK                                                                    |
| Row                                      | **V-08** — code + name read as separate elements; selected mark uses `accessibilityValue("Selected")` (good) |

#### S-V7: `CarryOverChip`

| Element                                  | Status                                                                 |
| ---------------------------------------- | ---------------------------------------------------------------------- |
| Composite chip                           | **V-04** — not collapsed to a single element                          |

#### S-V8: `RemainingBar`

| Element                                  | Status                                                                 |
| ---------------------------------------- | ---------------------------------------------------------------------- |
| Decorative bar                           | `.accessibilityHidden(true)` — OK                                     |

---

## Section 3 — Remediation plan

The following changes land in this same effort.

### Localization

- **L-01 / L-02 / L-03 (BLOCKER, BLOCKER, LOW)** — Replace the two `Button("Cancel", role: .cancel) {}` literals with a localized `String(localized:)` call backed by a new shared catalog key `common.action.cancel` (translator comment: "Generic Cancel button used in multiple confirmation dialogs and alerts."). Remove the stale empty `"Cancel"` orphan from the catalog.
- **L-04 (HIGH)** — In `SettingsView.displaySection`, render `"\(option.label) — \(option.example())"` (formatted via a new catalog key `settings.currencyDisplay.option.row` with two arguments). Update the picker row Text accordingly.
- **L-05 (MEDIUM)** — Replace `Text("\(appVersion) (\(buildNumber))")` with `Text(verbatim: "\(appVersion) (\(buildNumber))")` so the literal is **not** auto-extracted into the catalog. The version + build numerals are locale-invariant and the row's translatable copy ("Version 1.2.0, build 342") already lives on the row's localized `accessibilityLabel`. This removes the orphan `"%@ (%@)"` key and avoids exposing a `%@`-format string to translators with no meaningful context. (Earlier draft proposed adding a `settings.version.value` key with a comment; the verbatim path was chosen during review as more in line with typical iOS practice and is now codified in `docs/tech-design-doc.md §5.1` as the rule for locale-invariant strings.)
- **L-06 (LOW)** — Reword the comment on `addEditBudget.action.cancel` (or migrate this Cancel reuse to `common.action.cancel`). The remediation chooses the shared key path (cleaner long-term).

### VoiceOver

- **V-01 (HIGH)** — Add `.accessibilityAction(named:)` of "Delete" on each expense row that mirrors the swipe-to-delete handler. Localized via a new key `budgetDetail.expenseRow.accessibilityAction.delete`.
- **V-02 (MEDIUM)** — Make the current-period section header an `.accessibilityElement(children: .combine)` with a single coherent label "Current Day, total $20.00" via a new catalog key `budgetDetail.section.current.accessibilityLabel` (`%1$@, total %2$@`). Apply per-period.
- **V-03 (MEDIUM)** — Add `.accessibilityAddTraits(.isHeader)` to the `BudgetDetailView` status header.
- **V-04 (MEDIUM)** — Add `.accessibilityElement(children: .ignore)` to `CarryOverChip` so the explicit `.accessibilityLabel(...)` describes a single element.
- **V-05 (MEDIUM)** — Drop the redundant `.accessibilityAddTraits(.isStaticText)` on the chip in `BudgetRowView` and `BudgetDetailView` (V-04 already collapses the chip into a single static-text element).
- **V-06 (LOW)** — Add `.accessibilityHint("budgetDetail.resetCarryOver.button.accessibilityHint")` describing the destructive consequence.
- **V-07 (LOW)** — Add `.accessibilityHint("budgetDetail.menu.resetBudget.accessibilityHint")` to the destructive menu item.
- **V-08 (LOW)** — Add `.accessibilityElement(children: .ignore)` plus `.accessibilityLabel("\(code), \(name ?? "")")` and `.accessibilityValue(selectedValue)` to each currency row.

### Doc updates

- [`docs/product-features-planning.md`](../product-features-planning.md): bump **F-3.02 (VoiceOver)** and **F-3.03 (Internationalization of text)** statuses with a reference to this audit.
- [`docs/tech-design-doc.md`](../tech-design-doc.md) §5.1 / §5.2: codify the new conventions discovered (shared `common.*` keys; require `swipeActions` to be paired with `accessibilityAction`).

---

## Appendix A — Catalog statistics (pre-remediation)

| Metric                                        | Value |
| --------------------------------------------- | ----- |
| Total keys with `localizations`               | 100   |
| Keys with `state: "translated"` (English)     | 1 (`budgetDetail.resetBudget.dialog.message`) |
| Keys with `state: "new"` (English source)     | 99    |
| Empty / orphan keys                           | 1 (`"Cancel"`) |
| Keys missing `comment:`                       | 0 (other than the orphan) |

`state: "new"` simply means the source value has not yet been marked manually reviewed in Xcode; it does **not** indicate a missing English value. All keys do have an English value in the catalog.

## Appendix B — Pseudo-localization smoke procedure

This procedure does **not** mutate the shared scheme. It exercises every screen with bracketed accented expansions to surface truncation, missing keys, and bidirectional layout regressions.

```bash
# 1. Build for the configured simulator (see AGENTS.md > Build and test):
make build

# 2. Launch the app with pseudo-language args; doubles every string and wraps
#    each in markers so any unkeyed literal stays visibly English:
xcrun simctl launch booted com.jimmyho.simple-recurring-budgets \
  -AppleLanguages '(en-XA)' \
  -AppleLocale en_XA \
  -NSDoubleLocalizedStrings YES \
  -NSShowNonLocalizedStrings YES

# 3. RTL smoke (any layout breakage will show as flipped HStacks / unreversed
#    iconography):
xcrun simctl launch booted com.jimmyho.simple-recurring-budgets \
  -AppleLanguages '(ar)' \
  -NSForceRightToLeftWritingDirection YES
```

Walk every screen (Budgets list → Budget detail → Add/Edit Expense → Add/Edit Budget → Settings → Currency Picker) under each invocation; record results in the **Verification** appendix. Any string that appears in plain English (no expansion, no markers) is a missing-key defect.

> Bundle identifier subject to project entitlements; if the runtime bundle ID differs, replace `com.jimmyho.simple-recurring-budgets` with the booted app's actual ID (visible via `xcrun simctl listapps booted | grep -i Bundle`).

## Appendix C — Live VoiceOver walkthrough procedure

1. Open `Settings → Accessibility → VoiceOver` on the simulator (or device) and turn on VoiceOver, or toggle via `xcrun simctl ui booted appearance` settings as available.
2. Walk every screen in this order, exercising every interactive element in the sequence VO presents them:
   1. Budgets list (empty state)
   2. Budgets list (populated, with carry-over chip on at least one row)
   3. Budget detail (on-budget; carry-over enabled)
   4. Budget detail (over-budget)
   5. Budget detail (carry-over disabled)
   6. Add Expense sheet
   7. Edit Expense (push)
   8. Swipe-to-delete on an expense (VO: rotor → Actions)
   9. Add Budget sheet
   10. Edit Budget sheet (Delete Budget confirmation)
   11. Currency Picker
   12. Settings (all four iCloud states)
   13. Reset Carry-Over alert + Reset Budget confirmation
3. For each screen, record: focus order matches reading order (Y/N), every actionable control has a meaningful label (Y/N), destructive actions speak their consequence (Y/N), no raw symbol names ("plus.circle.fill") spoken (Y/N).

## Verification (post-remediation)

### Static / build verification (recorded by the implementing agent)

| Check                                                                 | Result | Notes |
| --------------------------------------------------------------------- | ------ | ----- |
| `make format`                                                         | PASS   | One file auto-reformatted; no manual fixups needed. |
| `make lint-fix` (SwiftLint `--fix` + strict gate)                     | PASS   | 0 violations across 65 files. |
| `make build` (bare `xcodebuild build`)                                | PASS   | `** BUILD SUCCEEDED **` on `iPhone 17,OS=latest`. |
| `make test` (Swift Testing + XCUITests on one iPhone simulator)       | PASS   | Full unit/UI suite green; `** TEST SUCCEEDED **`. |
| Static re-scan: 0 hard-coded UI literals                              | PASS   | Ripgrep over the same patterns as the inventory pass returns no matches. |
| Catalog: 0 orphan keys                                                | PASS   | Empty `"Cancel"` and auto-extracted `"%@ (%@)"` were removed. |
| Catalog: every key has a `comment:`                                   | PASS   | Verified by the catalog audit; new keys all carry translator comments. |
| All `swipeActions` paired with `accessibilityAction`                  | PASS   | The single `swipeActions` in `BudgetDetailView+ExpenseSection.swift` now has a matching `.accessibilityAction(named:)`. |
| Spec deviation L-04 fixed: Currency Display picker shows "label — example" | PASS | Wired via new `settings.currencyDisplay.option.row` key with two arguments. |
| `BudgetDetailView` status header carries `.isHeader` trait            | PASS   | Source confirms the trait is applied to the combined element. |
| `CarryOverChip` is a single VO element                                | PASS   | `.accessibilityElement(children: .ignore)` added. |
| Currency Picker row is a single VO element with composed label       | PASS   | `.accessibilityElement(children: .ignore)` + `.accessibilityLabel(...)` added. |
| Reset Carry-Over and Reset Budget controls speak destructive consequence | PASS | Both surfaces now have explicit `.accessibilityHint(...)`. |
| Catalog parses as valid JSON                                          | PASS   | `python3 -c "import json; json.load(open(...))"` succeeds. |

### Interactive verification (delegated to the human verifier)

The two interactive checks below cannot be completed by an autonomous agent and remain as procedures for the human verifier to execute. The procedures are documented in **Appendices B and C**.

| Check                                                                 | Result | Notes |
| --------------------------------------------------------------------- | ------ | ----- |
| Pseudo-loc walkthrough: no raw English keys visible on any screen     | TBD    | Run via `xcrun simctl launch` per Appendix B. |
| RTL walkthrough: no broken layout on any screen                       | TBD    | Run via `xcrun simctl launch` per Appendix B with `-NSForceRightToLeftWritingDirection YES`. |
| Live VO walkthrough: every checklist item passes                      | TBD    | Run per Appendix C on the booted simulator with VoiceOver on. |

Once the human verifier completes the interactive checks, this table should be amended with PASS/FAIL and any new findings should be filed as a follow-up change rather than re-opening this audit (the static substrate underneath is now in a known-good state).
