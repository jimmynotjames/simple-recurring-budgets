## Context

`AppSettings.weekStartDay` (F-5.01) is a global setting that grids every weekly budget at math-time. Today it is only viewable/editable in the Settings screen's Calendar section, with a confirmation alert that warns of the retroactive cascade. The Add/Edit Budget screen says nothing about week-start when Weekly is selected.

The UI and copy for this change were workshopped to a finalized state and are already committed on this branch (`AddEditBudgetView`, `AddEditBudgetViewModel`, new `WeekStartPickerScreen`, previews). This design records the technical decisions behind that committed UI so the spec/tasks and any future reader understand the "why". It does not re-open the UI/copy decisions.

## Goals / Non-Goals

**Goals:**
- Surface the active week-start day on the Add/Edit Budget screen when Weekly is selected, and let the user change it without abandoning the in-progress draft.
- Keep the setting honestly app-wide (the destination must not read as a per-budget control).
- Reuse the existing cascade-warning confirmation and `setting_changed` analytics rather than duplicating them.
- Fill the cross-cutting gaps (translations, accessibility, UI-test screen objects) and add unit coverage.

**Non-Goals:**
- Changing the global vs. per-budget model — week-start stays global (F-5.01).
- Combining the new screen with the Settings Calendar section — the two surfaces stay distinct by explicit decision.
- Changing any committed UI layout or text copy.
- Re-anchoring `startDate` in Edit mode.
- Any budget-math / data-model / schema change.

## Decisions

**1. Routing: push the picker onto the form's own `NavigationStack` (not replace-the-sheet, inline, or stash-and-restore).**
The Add/Edit Budget screen already hosts its own `NavigationStack`, so a `NavigationLink` to `WeekStartPickerScreen` pushes within the sheet, leaving the draft alive underneath and returning the user on Back. Alternatives rejected: setting the shared `Router.sheet = .settings` replaces the current sheet and discards the draft; an inline picker reads as a per-budget control (scope masquerade); a stash-and-restore handshake to the real Settings sheet is heavier and visually disruptive with no benefit over the push.

**2. A dedicated focused screen, not the full Settings screen, and kept separate from the Settings Calendar section.**
Pushing all of `SettingsView` would nest a second Done/title and unrelated sections, reading as "Settings inside a budget." A focused weekday list is cleaner. The Settings Calendar section keeps its menu-`Picker` form (a deliberate, user-approved divergence); the two share logic, not layout.

**3. Signal global scope three ways.** A read-before-acting scope banner ("App-wide setting. Changes here will update all weekly budgets."), a global-sounding title ("Start of Week"), and the existing cascade confirmation as the commit-time guardrail. Needed because a screen pushed from a budget form otherwise reads as budget-scoped.

**4. Reuse `WeekStartConfirmation`, the `settings.weekStart.alert.*` strings, and `setting_changed` analytics.** Single source of truth for the cascade warning and the analytics event; the picker is just a second caller. No new analytics event is introduced.

**5. Plain text banner (no markdown emphasis).** An earlier draft italicized "all weekly budgets" via markdown parsed to `AttributedString`. Dropped: markdown markers must be preserved and re-placed per locale, italics don't render meaningfully in non-italic scripts, and the failure mode shows literal asterisks. Plain text avoids all of it.

**6. Re-anchor scope: Add-mode, weekly only.** `realignWeeklyStartDate(to:)` recomputes the draft `startDate` to the most-recent-past occurrence of the new week-start when `AppSettings.weekStartDay` changes, mirroring the alignment `onPeriodChange` applies when Weekly is first tapped. It no-ops in Edit mode (an existing budget's `startDate` is real user data) and for non-weekly periods. This is a draft-UX nicety only — the weekly grid already follows the global setting at math-time, so no budget-math change is required.

## Risks / Trade-offs

- **Re-anchor clobbers a manual `startDate` edit** (user picks Weekly → manually sets a custom start → then changes the global week-start) → Accepted for simplicity; the re-anchor matches the "auto-populated default" mental model. Tracking a "user-touched startDate" flag to preserve manual edits is a possible future refinement.
- **Two parallel week-start UIs could drift** (Settings menu-picker vs. full-screen list) → Mitigated by sharing `WeekStartConfirmation` and the `settings.weekStart.alert.*` strings; the visual divergence is intentional, not accidental.
- **New source strings need translation** (4 keys) → Run the `translate-new-strings` pipeline as an apply task; plain-text copy keeps translation low-risk.
- **Screen objects going stale** (PRD §6.8.5) → Add a `WeekStartPickerScreen` screen object and update `AddBudgetScreen` for the new note/link as part of this change.

## Migration Plan

None. No data model, schema, or persisted-format change; the setting and its storage are unchanged. The app is pre-release (greenfield), so there is no migration or rollback surface.

## Open Questions

None.
