# Translation accessibility size check — audit log

Companion to this folder's `run.sh` / `README.md` / skill. Two parts:

- **Known issues / decisions** — findings inspected and consciously **accepted** (won't-fix) or
  deferred, so future runs don't re-litigate them. The skill reads this first and flags only *new* deltas.
- **Run history** — one dated entry per inspected run (verdict + any new findings), appended at the end
  of each inspection.

> Human/Claude-maintained, not auto-generated. Screenshots are ephemeral (`tmp/loc-size-check/`, deleted
> after inspection) — this file is the durable record.

## Known issues / decisions

### KI-1 — Sheet inline nav-title truncation (de, ru) — ACCEPTED · low
At forced `.xxxLarge`, the centered inline nav title on the **Add Budget** and **Add Expense** sheets
truncates in German and Russian (e.g. "Neues B…", "Добави…"). Other languages fit, **Settings** fits
everywhere, and the body content is clean. This is standard iOS behavior for an inline title squeezed
between Cancel/Save at large type, and the title is contextually redundant — **accept**. Revisit only if
we shorten the de/ru "Add budget" / "Add expense" nav strings.

## Run history

### 2026-06-04 · baseline · iPhone 17, iOS 26.5 · 10 locales × 7 screens @ xxxLarge
Established the baseline across **de, fi, ru, th, vi, ar, he, ja, zh-Hans, hi** at forced `.xxxLarge`.
**Layouts clean:** no body truncation; long budget names wrap; tall/stacked scripts (th, vi) and
Devanagari (hi) render without vertical clipping; CJK (ja, zh-Hans) is compact with no clipping; RTL
(ar, he) is fully mirrored; currency and calendars are locale-correct. Only standing caveat is **KI-1**.

### 2026-06-04 · full run · iPhone 17, iOS 26.5 · 10 locales × 8 shots (80 PNGs) @ xxxLarge · `59b9a69`
Full re-run across **de, fi, ru, th, vi, ar, he, ja, zh-Hans, hi** at forced `.xxxLarge` (7 parallel
clones). **No new findings — all layouts clean.** Body content fits/wraps everywhere; no clipping of
tall/stacked scripts (th, vi) or Devanagari (hi); CJK (ja, zh-Hans) compact and clean; RTL (ar, he)
fully mirrored with correct chevron/control placement, Hijri (ar) + Gregorian (he) calendars, and
₪/ر.س./Arabic-Indic numerals locale-correct. Size hook confirmed engaged (text visibly xxxLarge).
**KI-1 reproduced exactly as expected** in **de** ("Neues B…" / "Ausgabe…") and **ru** ("Новый…" /
"Добави…") inline nav titles on Add Budget / Add Expense; all other locales' nav titles fit fully.
*Non-layout observation (not a finding):* "Carry-Over" remains untranslated English in every non-en
locale (section header, toggle, green pill, menu items) — consistent across all 10, so it reads as an
intentional product term; flag for the translation track if that's not the intent.
