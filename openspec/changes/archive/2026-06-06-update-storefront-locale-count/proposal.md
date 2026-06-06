## Why

Apple expanded App Store Connect localization on 2026-03-31 and the app's shipped translation set grew from 38 to 49 storefront locales (landed in #194–#197). The `add-edit-expense-screen` spec still hard-codes "38 App Store storefront locales" in two localization requirements, so it now contradicts the canonical list in `docs/main-prd.md` §6.8.3 (and `scripts/translate_catalog/locales.py`). This is a docs-only reconciliation that removes the stale number entirely so the spec can never re-stale on a future expansion.

## What Changes

- **De-hardcode** the storefront-locale count in the two `add-edit-expense-screen` localization requirements. Instead of replacing "38" with "49" (which would re-stale next expansion), drop the literal number and require translations for *every App Store storefront locale listed in `docs/main-prd.md` §6.8.3 (F-3.03)* — the single canonical list. This matches the sibling specs (e.g. `budget-icon` says "all supported App Store storefront locales") and the requirement's own existing scenario step, which already reads "every storefront locale listed in F-3.03."
  - Requirement *"User-visible strings are registered in Localizable.xcstrings under the addEditExpense namespace"* — requirement text + the "All Add Funds keys are translated…" scenario heading.
  - Requirement *"Recents UI strings are keyed in Localizable.xcstrings"* — requirement text + the "Translations exist for…" scenario heading.
- No behavioral change: the requirements still mandate translation for the full shipped storefront set; only the way that set is named changes (canonical reference instead of a baked-in number).
- **No code, script, or pipeline changes.** No `Localizable.xcstrings`, Swift, or `scripts/` edits — the actual 49-locale translations already shipped in #194.

## Capabilities

### New Capabilities

- (none)

### Modified Capabilities

- `add-edit-expense-screen`: the two localization requirements stop hard-coding a storefront-locale count and instead reference the canonical list in `docs/main-prd.md` §6.8.3 / F-3.03 (requirement text + two scenario headings). No new/removed requirements; no behavioral change.

## Impact

- **Specs:** `openspec/specs/add-edit-expense-screen/spec.md` (4 occurrences of "38 storefront locales" → canonical reference, across 2 requirements). No other spec hard-codes a count.
- **Code / scripts / pipelines:** none.
- **Docs:** none required — this *removes* the spec's drift from `docs/main-prd.md` §6.8.3. No conflict with the PRD, tech-design, or feature IDs.

## Doc alignment

Skimmed `docs/main-prd.md` (§6.8.3 lists the 49 storefronts and is the canonical source the spec will now point to), `docs/product-features-planning.md` (F-3.03 is framed as the historical 38-locale build-out; current state points to §6.8.3), and `docs/tech-design-doc.md` (§5.1 keying rules, no count). No conflict — this change makes the lone stale spec defer to §6.8.3 instead of carrying its own number. No `docs/*.md` updates needed.
