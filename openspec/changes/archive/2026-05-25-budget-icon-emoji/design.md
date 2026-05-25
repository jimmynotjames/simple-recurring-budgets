## Context

F-4.03 calls for an optional per-budget icon. The UI, copy, model, and business-logic wiring for this feature are **already implemented** in the working tree (see proposal Impact). This design records the decisions behind that implementation and scopes the remaining gap-closing work — tests, translations, and accessibility verification — so the change can be applied and archived without drift versus `docs/`.

Current state in code:
- `Budget.icon: String?` exists with a defaulted init param; persisted via SwiftData, synced via CloudKit.
- `AddEditBudgetView` shows an icon chip beside the name; tapping opens `BudgetIconPicker` (a curated emoji grid sheet) bound to `viewModel.icon`.
- `AddEditBudgetViewModel` loads `icon` on edit, persists it on create/edit, and gates Save on an `iconChanged` diff.
- `BudgetsView`/`BudgetRowView` render the icon as a decorative name prefix; `BudgetDetailView` prefixes the nav title.
- `DebugData` seeds sample icons for previews.

## Goals / Non-Goals

**Goals:**
- Persist an optional single-emoji icon per Budget and surface it on the Budgets list and Budget detail.
- Keep the data model minimal (one optional `String`), CloudKit-safe, and migration-free.
- Centralize the curated emoji set in one code component as the master source.
- Meet the §6.8 cross-cutting bar: VoiceOver behavior, localized strings + translations, and (deliberately) no new analytics.
- Add automated tests covering model round-trip and the view-model create/edit/remove paths.

**Non-Goals:**
- SF Symbols as an icon source, Genmoji/custom-generated icons, LLM-guessed defaults, and photo upload — all **canceled** per F-4.03 / F-4.04 (not deferred).
- A name→emoji default suggestion (descoped).
- Showing the icon on the Add/Edit Expense screen or any surface beyond Budgets list + Budget detail.
- Free-text emoji entry or validation of arbitrary strings (the picker supplies known-good values).

## Decisions

**Store the icon as `Budget.icon: String?` (one optional column).**
Rationale: the icon is "exactly one emoji," and a Swift `Character` is neither a SwiftData-storable type nor a guarantee of emoji-ness, so `String?` is the idiomatic store with `nil` = none. Single optional column means no asset storage, no discriminator, and an additive CloudKit-safe field. Alternatives rejected: a `Character` type (not persistable), an enum/multi-type icon (only needed if non-emoji sources existed — they're canceled), external `Data`/CKAsset (photo-only concern, canceled).

**Generic field name `icon`, emoji-only feature.**
Rationale: the feature is semantically a Budget "icon" (matching F-4.03 wording and giving the column room if scope ever broadened), while the only implemented source is the curated emoji set. The VM/UI use `icon` consistently; "emoji" survives only in comments noting the implementation.

**Curated grid picker, not the system emoji keyboard.**
Rationale: there is no public API to force the emoji keyboard, and a raw text field yields a cursor with no guaranteed emoji UX and untrusted free text. A curated `BudgetIconPicker` sheet works in previews and on device, guarantees known-good single-emoji values (no sanitizer needed), and matches the "calm, tidy" curation goal. The picker component is the single master source for the set; specs/docs intentionally do not enumerate it. Trade-off: not the full Unicode catalog — accepted.

**Icon rendered as a name prefix via `Text` concatenation.**
Rationale: composing `icon + " " + name` in a single `Text` makes the emoji read as part of the name (one space gap), wraps naturally, and lets the row's existing composed accessibility label remain authoritative — so the icon stays decorative for VoiceOver. On the detail screen the icon prefixes the `navigationTitle` string (mirrors the row). Trade-off: the detail nav title's VoiceOver announcement includes the emoji; accepted as a minor, expected consequence of putting it in the title (documented in the spec).

**No new analytics.**
Rationale: an icon is cosmetic; per F-8.02 scope it only contributes to the existing aggregate `budget_edited` change gate, with no new event or property.

**Gap-closing = tests + translations + a11y verification.**
The behavior is built; this change adds Swift Testing coverage (model persistence/round-trip; VM create with/without icon, edit-change, edit-remove, icon-only edit still saves), runs the translation pipeline for the new keys (and reconciles orphaned former `emoji` keys), and verifies the VoiceOver/Dynamic Type behavior asserted in the specs.

## Risks / Trade-offs

- **Orphaned localization keys** (former `addEditBudget.field.emoji.*` / `addEditBudget.emojiPicker.*` renamed to `icon`) → Run the translate pipeline for the new keys and remove/let the catalog reconcile the stale ones; verify with the project's `check_translations` step before archive. The renamed keys were never translated, so no localized content is lost.
- **Detail nav-title VoiceOver reads the emoji** → Documented as expected in the spec; if it proves noisy, a follow-up could move to a custom toolbar principal item with a separate accessibility label. Out of scope here.
- **Emoji rendering at large Dynamic Type / dark mode** → Emoji are multicolor and don't tint; verify the chip, list prefix, and picker remain legible at xxxLarge and in dark mode (preview-level check).
- **Curated set drift between code and any documentation** → Mitigated by making the picker the sole master source and explicitly not enumerating the set in specs/docs.

## Migration Plan

No data migration. `Budget.icon` is an additive optional attribute on the in-place `SchemaV1` (app is unreleased/greenfield), so SwiftData handles it as a lightweight automatic change and CloudKit treats it as a new optional field. Rollback is trivial (the field is unused if the feature is reverted; existing records read `nil`).

## Open Questions

None. Scope is settled by the updated F-4.03 (curated emoji set; alternatives canceled). Doc alignment confirmed in the proposal — no conflicts with `docs/main-prd.md`, `docs/product-features-planning.md`, or `docs/tech-design-doc.md`.
