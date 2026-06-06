## Context

The locale expansion (#194–#197) grew the shipped translation set from 38 → 49 storefront locales. `docs/main-prd.md` §6.8.3 is the canonical storefront list (enumerates all 49) and `scripts/translate_catalog/locales.py` is the machine source of truth (also 49). The `add-edit-expense-screen` spec is the only `openspec/specs/` file that still hard-codes "38" (four occurrences across two localization requirements), so it has drifted from §6.8.3. This is a documentation-only reconciliation.

## Goals / Non-Goals

**Goals:**
- Bring the two `add-edit-expense-screen` localization requirements into agreement with the canonical storefront list, in a way that won't drift again.
- Keep the change purely textual — no behavioral change to the requirements (they already mandate "translated for every shipped storefront locale").

**Non-Goals:**
- No code, `Localizable.xcstrings`, Swift, `scripts/`, or pipeline changes — the 49-locale translations already shipped in #194.
- No change to any other spec (none hard-code a count).
- No change to `docs/*.md` (this *removes* drift from §6.8.3 rather than introducing any).

## Decisions

**Decision: De-hardcode the count — reference the canonical list instead of baking in a number.**
Replace "all 38 App Store storefront locales" with "every App Store storefront locale listed in `docs/main-prd.md` §6.8.3 (F-3.03)", and drop the number from the two affected scenario headings ("…to every storefront locale" / "Translations exist for every storefront locale"). Rationale:
- **Won't re-stale.** The next storefront expansion updates only §6.8.3 / `locales.py`; this spec automatically follows.
- **Consistent with the rest of the spec corpus.** Sibling specs (`budget-icon`, etc.) already say "all supported App Store storefront locales", and this requirement's own existing scenario step already reads "every storefront locale listed in F-3.03" — so the requirement body and scenario headings now match that phrasing.
- **Single source of truth.** §6.8.3 is the canonical list humans and specs are pointed at; the spec defers to it rather than duplicating a number that can disagree with it.

- *Alternative considered — literal bump 38 → 49.* Minimal edit, but it just re-creates the same drift the next time the locale set changes, and leaves this spec inconsistent with the generically-phrased sibling specs. Rejected in favor of de-hardcoding.

## Risks / Trade-offs

- [A reader can no longer see the exact locale count inline in this spec] → Mitigation: the requirement names the canonical source (`docs/main-prd.md` §6.8.3) one click away, which is authoritative and always current; an inline number would only risk disagreeing with it.

## Doc alignment

Aligns with `docs/main-prd.md` §6.8.3 (canonical storefront list) and `docs/tech-design-doc.md` §5.1 (keying rules, no count). No conflicts; no `docs/*.md` updates required.
