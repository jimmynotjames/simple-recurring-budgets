## 1. ViewModel: reveal latch + amount protection

- [x] 1.1 In `AddEditExpenseViewModel`, add an observed `private(set) var recentsRevealedInEdit = false` reveal latch.
- [x] 1.2 Add a `name` property `didSet` that sets `recentsRevealedInEdit = true` when the trimmed value is empty (one-way; never reset to `false`). Confirm it does not interfere with the existing `isAddFunds` seed or `applyRecent` writes.
- [x] 1.3 In `init(editing:)`, set `recentsRevealedInEdit` from whether the seeded trimmed `name` is empty (initializer assignment skips the `didSet`, so set it explicitly).
- [x] 1.4 In `init(editing:)`, set `amountProvenance = .userTyped` after seeding `amount = expense.displayAmount`, so a single Recents tap protects the existing amount. Verify `init(adding:)` provenance behavior is unchanged (`.empty`).

## 2. Visibility wiring

- [x] 2.1 In `AddEditExpenseView+RecentsSection.swift`, change `shouldShowRecentsSection` to `hasRecentSources && (!isEditing || recentsRevealedInEdit)`.
- [x] 2.2 Update the `shouldShowRecentsSection` docstring and the `recentsSection` view-entry docstring (currently state Edit mode never shows Recents) to describe the blank-Description-gated, persist-once-shown reveal.

## 3. Analytics

- [x] 3.1 Add a `from_screen` property to the `expense_recent_reused` emission in `applyRecent` (`add_sheet` in Add mode, `budget_detail` in Edit/View mode), threaded from the call-site mode. Confirm exactly one event still fires per interaction (double-tap does not double-emit).
- [x] 3.2 Update `docs/analytics-spec.md` §9–§10: extend the `expense_recent_reused` catalog description to cover Edit mode and document the new `from_screen` property values; add a Revision-History entry.

## 4. Tests

- [x] 4.1 Update `AddEditExpenseViewModelRecentsTests.swift` `shouldShowRecentsSection_falseInEditModeEvenWithSources` to reflect the latch (hidden only until revealed).
- [x] 4.2 Add VM tests: latch true on blank-on-open edit; latch false on non-blank-on-open edit; latch flips true when Description cleared and persists after re-type / tile tap; latch irrelevant in Add mode (always shown when candidates exist).
- [x] 4.3 Add Edit-mode provenance tests: single tap fills Description only and preserves the seeded amount; double-tap full replace overwrites both; clearing the amount re-arms single-tap fill.
- [x] 4.4 Add an analytics test asserting `from_screen` is `add_sheet` in Add mode and `budget_detail` in Edit mode on `expense_recent_reused`.

## 5. Previews and UI test screen objects

- [x] 5.1 Update the "Recents — Edit mode (no section)" preview in `AddEditExpenseView+RecentsSection.swift` to reflect the new behavior (e.g. a blank-Description Edit preview that shows the section, plus a non-blank Edit preview that hides it).
- [x] 5.2 Review `simple-recurring-budgetsUITests/` screen objects (`AddExpenseScreen`, `BudgetDetailScreen`) for any assumption that Edit mode lacks a Recents row; update if a journey now reaches it. Run `make test-ui` if screen objects change.

## 6. Cross-cutting concerns

- [x] 6.1 Accessibility: no new controls — the revealed section reuses existing Recents labels/hints/custom action and `@ScaledMetric` geometry. Verify the reveal does not strand VoiceOver focus; no new a11y work expected.
- [x] 6.2 Localized source strings: confirm no new user-facing strings are introduced (the `from_screen` value is internal analytics, not UI). If any are added, key them under `addEditExpense.*` with a translator `comment:`.
- [x] 6.3 Translations: run the `translate-new-strings` skill only if step 6.2 added/renamed keys; otherwise it no-ops. End on a clean `check_translations.py`.
- [x] 6.4 Mixpanel: covered by §3 (new `from_screen` property + analytics-spec sync).

## 7. Docs

- [x] 7.1 Update `docs/product-features-planning.md` F-7.04: extend the Add-only framing to document the Edit-mode blank-gated reveal and the Edit tap-semantics (single = Description, double = Description + amount; existing amount protected).
- [x] 7.2 Verify `docs/tech-design-doc.md` needs no change (no architecture/schema/sync impact); note in the change if confirmed clean.

## 8. Gate

- [x] 8.1 Run `make gate` (format → lint-fix → build → test) and resolve any failures.
- [x] 8.2 Run `make test-ui` if any screen object or navigable Edit-mode journey changed. (Screen objects unchanged; skipped.)
