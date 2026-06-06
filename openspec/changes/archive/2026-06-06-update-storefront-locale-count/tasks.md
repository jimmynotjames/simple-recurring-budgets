## 1. Reconcile the spec count

- [x] 1.1 Verify the delta's two MODIFIED requirement headings match the live headings in `openspec/specs/add-edit-expense-screen/spec.md` exactly (so archive-sync applies cleanly): "User-visible strings are registered in Localizable.xcstrings under the addEditExpense namespace" and "Recents UI strings are keyed in Localizable.xcstrings".
- [x] 1.2 On archive, sync the delta so the main spec's two localization requirements **de-hardcode** the count — 4 occurrences updated from "38 storefront locales" to "every App Store storefront locale listed in `docs/main-prd.md` §6.8.3 (F-3.03)" (two requirement bodies) and the two scenario headings drop the number ("…to every storefront locale" / "Translations exist for every storefront locale").

## 2. Verify

- [x] 2.1 Run `/opsx:verify` (openspec validate) — the delta parses and both MODIFIED headers resolve against the main spec.
- [x] 2.2 After sync, confirm `grep -rn "\b38\b" openspec/specs/` returns nothing, and that no `49` (or any other literal count) was introduced — the spec now defers to §6.8.3 / F-3.03 with no baked-in number.
- [x] 2.3 Confirm the phrasing matches the sibling specs' generic style and the requirement's own existing "every storefront locale listed in F-3.03" scenario step.
- [x] 2.4 No `make build` / `make test` — docs-only change; no `Localizable.xcstrings`, Swift, `scripts/`, or pipeline edits.
