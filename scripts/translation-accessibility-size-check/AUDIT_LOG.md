# Translation accessibility size check — audit log

Companion to this folder's `run.sh` / `README.md` / skill. Two parts:

- **Known issues / decisions** — findings we've inspected and consciously **accepted** (won't-fix) or
  **deferred**, so future runs don't re-litigate them. **The skill consults this first** and flags only
  *new* (delta) findings; acknowledged ones get a one-line mention.
- **Run history** — one dated entry per inspected run (verdict + any new findings).

> Human/Claude-maintained, **not** auto-generated. The screenshots themselves are ephemeral
> (`tmp/loc-size-check/`, deleted after inspection) — **this file is the durable record.** Append a
> Run-history entry at the end of every inspection (the skill prompts it), and promote any newly
> accepted finding into Known issues with its rationale.

---

## Known issues / decisions

Each entry: `ID` · status · severity · finding · decision + rationale · first seen.

### KI-1 — Sheet inline nav-title truncation (de, ru) — **ACCEPTED** · low
- **Finding:** At forced `.xxxLarge`, the centered inline navigation title truncates on the **Add Budget**
  and **Add Expense** sheets in German and Russian:
  - de: "Neues Budget" → "Neues B…", "Ausgabe hinzufügen" → "Ausgabe…"
  - ru: "Новый бюджет" → "Новый…", "Добавить расход" → "Добави…"
  - fi / th / vi / ar / he titles fit; **Settings** title fits in every language; **body content is clean**.
- **Decision:** Accept. Standard iOS behavior for an inline title squeezed between Cancel/Save at large
  type; the title is contextually redundant (the user just tapped that action). Not a layout breakage.
- **Revisit if:** we shorten the de/ru "Add budget" / "Add expense" nav strings, or drop the inline titles.
- First seen: 2026-06-04.

### KI-2 — Add Budget period selector hidden by keyboard — **RESOLVED** · tool gap
- **Finding:** The name field auto-focuses on the Add Budget sheet, so the keyboard covered the lower
  period-button rows; the longest biweekly label — Finnish **"Kahden viikon välein"** — was obscured and
  unverified at xxxLarge.
- **Resolution (2026-06-04):** The capture now dismisses the keyboard (taps the selected period chip — no
  production change) and takes a second scrolled shot (`03b-add-budget-lower`), so the full period grid +
  schedule + carry-over are visible at xxxLarge. **Re-verified de + fi:** the Finnish biweekly chip
  **wraps to two lines within its tile with no truncation**; every period chip renders cleanly. No app
  defect — the blind spot was the capture's, and it's closed.
- First seen: 2026-06-04.

### Cross-references (not layout findings — don't re-flag here)
- **GitHub #181** — `make test`'s `testAddBudgetFormBlank` fails on iOS 26.5 because a system keyboard
  `TUIPredictionViewCell` bleeds into the sheet's a11y tree (sufficient-description audit). Pre-existing,
  unrelated to layout; tracked separately.

---

## Run history

Newest first. Entry: date · run label · device / iOS · scope · git SHA · verdict.

### 2026-06-04 · KI-2 fix verification · iPhone 17, iOS 26.5 · de + fi, Add Budget only @ xxxLarge
Targeted re-run after teaching the capture to dismiss the keyboard + take a scrolled `03b` shot.
**Verdict: KI-2 resolved.** Full Add Budget period grid now visible at xxxLarge; Finnish
"Kahden viikon välein" wraps to two lines in its tile with no truncation. (Full 7-locale re-run with the
new `03b` shots not yet done — deferred to the next pre-submission pass; the 5 untested languages all have
short period labels that already fit.)

### 2026-06-04 · post-fix re-run · iPhone 17, iOS 26.5 · 7 locales × 7 screens @ xxxLarge · `4796e5d`
**Verdict: clean.** All three sheet screens (Add Budget, Settings, Add Expense) now render at true
xxxLarge after the sheet Dynamic Type fix. No body truncation in any of the 7 languages; long budget
name wraps; tall/stacked scripts (th, vi) render without clipping; RTL (ar, he) fully mirrored;
calendars (Hijri for ar_SA, Gregorian elsewhere) and currency locale-correct. Outstanding findings
limited to **KI-1** (accepted) and **KI-2** (tool gap).

### 2026-06-04 · initial run · iPhone 17, iOS 26.5 · 7 locales × 7 screens @ xxxLarge · `66d07dc`
List & detail screens clean at xxxLarge. **Bug found:** the three sheet screens (Add Budget, Settings,
Add Expense) were rendering at *default* size, not xxxLarge — the root-level Dynamic Type override did
not cross the `.sheet` presentation boundary, so those screens weren't actually being stress-tested at
large type. Fixed in `4796e5d` (re-apply the inert override inside `RootView`'s sheet content);
re-validated in the post-fix run above.
