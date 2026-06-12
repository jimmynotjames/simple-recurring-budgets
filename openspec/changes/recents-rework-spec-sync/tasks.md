# Tasks: recents-rework-spec-sync

> Context: the Recents rework code is already merged into PR #244 and pinned by unit tests. These tasks cover the one remaining code touch (bucket relabel), the docs sync, and verification. The delta spec in this change folder is the wording source of truth for the doc edits.

## 1. Analytics bucket relabel (only code touch)

- [x] 1.1 In `simple-recurring-budgets/Logging/Analytics+DomainExtensions.swift`, change `recentsVisibleCountBucket`'s default case label from `"8-15"` to `"8+"` and update its doc comment to note the open-ended top bucket under the 30-tile display cap.
- [x] 1.2 Update the expectation in `simple-recurring-budgetsTests/Logging/RecentsBucketingTests.swift` (or wherever `recentsVisibleCountBucket` is asserted — locate via the existing `RecentsBucketingTests` suite) from `"8-15"` to `"8+"`, and add/extend a case asserting a count above 15 (e.g. 30) maps to `"8+"`.

## 2. Docs sync

- [x] 2.1 `docs/analytics-spec.md` §3: update the `expense_recent_reused` / `recents_visible_count` row's allowed values from `0 / 1 / 2-3 / 4-7 / 8-15` to `0 / 1 / 2-3 / 4-7 / 8+`, and append a note to the `expense_recent_reused` event row that the double-tap full replace emits no second event and the event fires whether the amount was filled or preserved (provenance rule).
- [x] 2.2 `docs/product-features-planning.md` F-7.04: update the entry to match the delta spec — acceptance criterion "Reuse name + amount" gains the amount-provenance rule and the double-tap/VoiceOver full replace; "Suggestion → autocomplete" notes the section sits below the Description field; Edge Cases "Ranking" describes base tile + recurrence-gated variants (≥3 occurrences, max 2 extras per name, clustered) and the corpus (200) vs display (30) cap split; append this change's name to the Status line.
- [x] 2.3 `docs/tech-design-doc.md`: no change needed — the two Recents mentions (line 67 VM responsibility list, line 460 shipped-features roll-up) are placement/algorithm-neutral.
- [x] 2.4 Skimmed `docs/main-prd.md` §6.8 and §8.3 — no contradictions; no edits.

## 3. Verification

- [x] 3.1 Run the four-step gate (`make format && make lint-fix && make build && make test` per AGENTS.md) — all green; the two Recents unit suites and `RecentsBucketingTests` must pass with the relabel. (684 unit tests green; one UI load-flake retried to green on a simulator-contended run.)
- [x] 3.2 Run `openspec validate recents-rework-spec-sync` — change is valid.
- [x] 3.3 Cross-check the delta spec against the implementation on PR #244 one final time (placement, caps 30/200/3/2, provenance behaviors, double-tap, clear button, localization keys) — verified, no mismatches.
- [x] 3.4 Committed `e52fd4d` on `recents-ux-workshop`; PR #244 body rewritten — "Known-stale" replaced with the formalization summary and the intentionally-deferred future candidates.
