# Releases

All notable App Store releases of **Wren** are logged here, newest first.

This file is distinct from the other product docs: `[docs/product-features-planning.md](docs/product-features-planning.md)` tracks each feature's status across its own lifetime (not release-scoped), and `[docs/main-prd.md](docs/main-prd.md)` is the living source of truth for current product requirements. This file is an append-only, release-scoped record — what shipped in each version, plus confirmation that the [cross-cutting concerns](docs/main-prd.md#68-cross-cutting-ongoing-concerns) held at that point in time.

Entries cross-reference feature IDs (`F-x.xx`) rather than re-describing them — see `product-features-planning.md` for full acceptance criteria and implementation history.

## Format

Each release entry follows this shape:

```
## vX.Y.Z — YYYY-MM-DD

**Submitted:** YYYY-MM-DD · **Build:** N · **App Store version:** X.Y.Z

### Features shipped
- F-x.xx — short label
- F-x.xx — short label

### Cross-cutting concerns confirmed
- **Localization:** NN storefront locales (PRD §6.8.3)
- **Light/Dark Mode:** confirmed on both appearances
- **Accessibility:** Dynamic Type + VoiceOver spot-checked
- **Analytics:** consent flow + event coverage verified
```

---



## v1.0 — Released 2026-07-22

**Submitted:** 2026-07-13 · **Build:** 17 · **App Store version:** 1.0

### Features shipped

- F-1.01 — App Scaffolding
- F-1.02 — Data Architecture
- F-2.01 — Budgets screen
- F-2.02 — Budget screen
- F-2.03 — Add/Edit Budget screen
- F-2.04 — Add/Edit/View Expense Item screen
- F-2.05 — Settings screen
- F-2.06 — First-run empty state
- F-2.07 — Carry-over toggle switch
- F-2.08 — Specific Dates budget type
- F-3.01 — Dynamic Type (initial build-out)
- F-3.02 — VoiceOver (initial build-out)
- F-3.03 — Internationalization of text (initial build-out)
- F-3.04 — Internationalization of currency
- F-3.05 — Dark Mode (initial build-out)
- F-4.03 — Budget icon (curated emoji set)
- F-5.01 — Configurable start of week
- F-6.01 — Manually adding funds
- F-6.03 — App Store rating prompt
- F-7.04 — Recently used expenses
- F-7.05 — Per-budget period start date
- F-7.06 — Pause and Resume a Budget
- F-7.07 — Per-budget end date
- F-8.01 — Diagnostic logging via OSLog
- F-8.02 — Mixpanel Phase 1 — foundation and basic stats



### Cross-cutting concerns confirmed

- **Localization:** 49 storefront locales ([PRD §6.8.3](docs/main-prd.md#683-localization--source-strings-and-translations))
- **Light/Dark Mode:** confirmed on both appearances
- **Accessibility:** Dynamic Type + VoiceOver initial build-outs complete (F-3.01/F-3.02); ASC Accessibility Nutrition Label filled in
- **Analytics:** Mixpanel Phase 1 (F-8.02) live; consent flow locale-aware, no PII collected

