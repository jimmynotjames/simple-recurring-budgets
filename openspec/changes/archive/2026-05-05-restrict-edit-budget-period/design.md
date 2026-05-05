## Context

The Add/Edit Budget sheet (`AddEditBudgetView` + `AddEditBudgetViewModel`) ships under the `add-edit-budget-screen` capability and satisfies F-2.03 / F-3.04. The branch `u/jimmyho/xcode+claude/restrict-edit-budget` already contains a "UI workshopping" commit that:

1. Makes period chips static (non-button) in Edit mode and adds a `lock.fill` caption explaining the lock.
2. Adds an inline caption when the user changes currency from the value at sheet-open time, clarifying that no FX conversion is performed.

Two gaps remain. First, the model layer still allows period to be written back to a `Budget` in Edit mode (`AddEditBudgetViewModel.saveEdit` includes a `period` branch in its field comparison), so the new product rule is enforced only by the UI. Second, the locked period chips lose their button trait without picking up an explanatory hint, leaving VoiceOver users without a signal that the control is intentionally disabled.

This design closes both gaps and aligns the spec and product docs with the new rule.

## Goals / Non-Goals

**Goals:**

- Enforce period immutability post-creation as a model-layer invariant in `AddEditBudgetViewModel.saveEdit`, not just a UI affordance.
- Convey the locked-state to VoiceOver users with a short hint string.
- Surface "currency change is label-only, no conversion" both visually (already done) and audibly via VoiceOver when the caption first appears.
- Update F-2.03 acceptance criteria, F-3.04 acceptance criteria, and the `add-edit-budget-screen` spec to match.
- Translate the three new keys across all 38 storefront locales.

**Non-Goals:**

- No visual design or main-display copy changes — chip styling, caption wording, lock-icon usage, layout, animation, and color choices stay as authored on this branch.
- No analytics changes. `budget_edited` already fires for Edit-mode saves and its `period` property remains correct; we do not introduce a "period change attempted while locked" event.
- No data migration. `Budget.period` remains a stored `String` and the SwiftData / CloudKit schema is unchanged.
- No global PRD or tech-design doc updates. Only `docs/product-features-planning.md` (F-2.03 and F-3.04) needs an acceptance-criterion edit.
- No retroactive change to existing `Budget` rows. Period values stored before this change are accepted as-is and read on Edit; the rule only constrains future writes.

## Decisions

### D1 — Drop `period` from `saveEdit`'s field comparison

**Choice.** Remove the `period` branch from `AddEditBudgetViewModel.saveEdit`. After this change, `Budget.period` is written exactly once: at insert in `saveNew`. Edit-mode `save` ignores `viewModel.period` regardless of whether it differs from `Budget.period`.

**Rationale.** The product rule "period is immutable after creation" needs a single source of truth. UI-only enforcement is fragile (a future ViewModel mutation, programmatic seed, or refactor could silently re-introduce period mutation). Leaving the comparison in place but inserting a guard would still semantically allow the write — explicitly omitting the field is clearer and matches what the spec is going to say.

**Alternatives considered.**

- **Keep the comparison; precondition-fail in `saveEdit` if it differs.** Heavier handed. A `precondition` would crash in production if any defensive path mutated `viewModel.period` (e.g. a future bulk-import or undo flow). The rule isn't life-or-death; silently ignoring a divergent draft is the right behavior.
- **Add a `private(set)` guard on `viewModel.period` itself in Edit mode** (e.g., `period`'s setter no-ops when `isEditing`). Surprising — code reading `vm.period = .monthly` would expect the value to take effect. We prefer the canonical assignment to remain free; only persistence is constrained.

### D2 — `viewModel.period` remains assignable in both modes; the binding stays simple

The view model exposes `var period: BudgetPeriod` for both modes. We do not add a mode check on the setter. The view, in Edit mode, simply does not render an interactive control that would assign to it. This keeps the existing tests (which freely set `vm.period`) working and avoids paying a re-design cost for a field that's already locked at the persistence layer.

### D3 — Accessibility hint on locked period chips

Add a new key `addEditBudget.chip.period.locked.accessibilityHint` ("Locked. Period can't be changed after creating your budget.") and apply it via `.accessibilityHint(...)` on the Edit-mode branch of `periodChip(_:)` only. The Add-mode branch keeps no hint (chips are unambiguously tappable buttons). The selected chip continues to carry `.isSelected`; the non-selected chips carry no selection trait.

We do **not** override the chip's `.accessibilityLabel` to include "locked" because the existing per-period label (e.g. "Daily period") is reused across both modes; mixing modes into the label complicates the localized-string keys for what's better expressed as a hint.

### D4 — VoiceOver announcement when the currency caption first appears

The currency-change inline caption is rendered conditionally (`if !initialCurrencyCode.isEmpty, viewModel.currencyCode != initialCurrencyCode`) and animates in. A sighted user notices it; a VoiceOver user might not, because focus remains on the currency picker row that just dismissed.

**Choice.** Use `.onChange(of: viewModel.currencyCode)` to post `AccessibilityNotification.Announcement(...)` with the localized caption text the first time `currencyCode` diverges from `initialCurrencyCode` after sheet open. Subsequent divergences (e.g., the user picks a third currency) re-announce — that's acceptable and arguably correct: the disclaimer applies to any change from the initial.

**Alternatives considered.**

- **Move VoiceOver focus to the caption.** Disruptive — it would yank focus away from where the user just was (the currency picker).
- **Set `.accessibilityElement(children: .combine)` on the parent VStack and rely on default re-read.** SwiftUI doesn't reliably announce newly-appearing siblings in a parent already announced; the `Announcement` API is the supported path.

### D5 — Locale catalog: three new keys, all in `addEditBudget.*`

- `addEditBudget.note.periodLocked` (already on branch) — caption text under the period grid.
- `addEditBudget.note.currencyLabelOnly` (already on branch) — caption text below the currency row.
- `addEditBudget.chip.period.locked.accessibilityHint` (new in this change) — VoiceOver hint on locked chips.

All three go through `scripts/translate_catalog/` (extract → translate → merge → validate) for the 38 storefront locales before this change is treated complete. This follows F-3.03 / `docs/main-prd.md` §6.8.

### D6 — Tests target the model-layer invariant only

We add Swift Testing cases in `AddEditBudgetViewModelTests.swift`:

- `editMode_save_periodChangeIsIgnored` — set `vm.period` to a value different from the seeded one, call `save`, assert `Budget.period` is unchanged AND `Budget.lastModified` is unchanged (because nothing else changed).
- `editMode_save_periodChangeAlongsideOtherChange_writesOtherButNotPeriod` — change `name` AND `period`, assert `name` is written, `period` is not, `lastModified` is bumped exactly once.

We do not add UI tests for the locked-state visual or accessibility hint — the project's posture is to keep UI tests minimal (the existing UI test plan skips business-logic UI tests in scripted runs per `AGENTS.md`). Manual VoiceOver verification on hardware covers the rest, and is already part of the F-3.02 ongoing checklist.

## Risks / Trade-offs

- **[Risk] Silent ignore of `vm.period` on save in Edit mode could surprise a future contributor reading `saveEdit`.** → **Mitigation:** add an inline comment in `saveEdit` referencing F-2.03's immutability rule and this change name; mirror the rationale in the spec's `Save in Edit mode...` requirement. Add a unit test that documents the behavior (D6).
- **[Risk] VoiceOver `Announcement` posts may double-announce on rapid re-selection of the same currency.** → **Mitigation:** the announcement is cheap and rare (one tap of the currency pill); we deliberately accept this in D4. If it becomes annoying we can debounce.
- **[Risk] Translations lag.** New keys without 38-locale coverage would ship with English fallback strings. → **Mitigation:** include the translate-catalog run as a hard task before archive (per F-3.03).
- **[Trade-off] We do not block `vm.period` mutation in Edit mode.** A test that asserts the binding-level immutability would fail; existing tests that set `vm.period` keep working. We accept the broader binding API in exchange for a cleaner test surface and a simpler view-model.

## Migration Plan

No data migration. Existing `Budget` rows keep their stored `period`. No SwiftData schema version bump or CloudKit record-type change. Rollout is a pure in-app code + spec + docs update; CloudKit-synced devices on older app versions still write `period` from their UI (the rule is enforced by the new app version, not the data layer).

## Open Questions

None at this time.
