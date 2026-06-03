# Translation Quality Audit — 2026-06-02

> **Plan + living progress tracker.** This document is both the implementation plan and
> the status record for the in-app translation tone/cultural/length audit. It will be
> written to `docs/audits/translation-quality-audit-2026-06-02.md` and updated as each
> track lands. Work proceeds in phases, potentially across multiple commits/PRs.

**Author/Owner:** Jimmy Ho · **Driver:** Claude (autonomous) · **Started:** 2026-06-02

## Status

| Track | Scope | Status | Landed in |
| --- | --- | --- | --- |
| **A** | Strengthen translation prompt + register/cultural notes + length discipline | ✅ Complete | `translations-audit-track-a` |
| **B** | Audit sub-pipeline (extract-with-translations, auditor, report) | ✅ Complete | `translations-audit-track-a` |
| **C** | Triage → targeted re-translation → re-audit | ✅ Complete (84% of flagged pairs cleared) | `translations-audit-track-a` |
| **Supporting** | settings allowlist, README, audit-translations skill | ✅ Complete | `translations-audit-track-a` |
| **Follow-up** | Layout-truncation UI verification (optional) | ⬜ Deferred | — |

Legend: ⬜ not started · 🟡 in progress · ✅ complete · ⛔ blocked · ⏸ deferred.

## Working mode (autonomous)

Per owner's request, execute as autonomously as possible:
- **Proceed without pausing for approval** on each track; use best judgment when choices
  arise rather than blocking. Routine dev-workflow steps (branch/commit/PR, build, lint,
  tests) are done, not asked.
- **Phase the work.** Each track (A, B, C) is a self-contained commit/PR where practical.
  Update this doc's Status table and the **Issues & decisions log** as each lands.
- **Log, don't block.** When something is ambiguous, judgment-dependent, or turns out
  differently than planned, record it in the **Issues & decisions log** at the bottom with
  the decision taken, and surface a consolidated summary to the owner at the end of each
  phase. Anything genuinely destructive or one-way-door is the exception — flag those.

## Context

v1 is stable. Every in-app string in `Localizable.xcstrings` (249 keys × 37 target
locales) was translated by the `translate-new-strings` pipeline using **Claude Haiku**
(`.claude/agents/translation-locale.md` defaults to `model: haiku`). The concern is
**quality, not coverage**: that non-English translations may be off-tone (not the
"calm, tidy, quietly warm, understated" voice in `docs/ux-design-brief.md`), use the
wrong formality register, be culturally inappropriate, or run **too long** for the
app's tight UI layouts (truncation / awkward wrapping).

Nothing in the current pipeline can catch this. The two gates that run —
`scripts/translate_catalog/validate.py` and `scripts/check_translations.py` — are
purely **structural** (format specifiers preserved, every key present, state =
`translated`, not byte-identical to English). A grammatically valid but tonally wrong,
or overly long, translation passes all of them silently.

Three root causes make this likely and would make any audit findings recur:
1. **The translation prompt under-specifies the voice.** `scripts/translate_catalog/PROMPT_TEMPLATE.md:21`
   says only *"Friendly, concise, natural UI copy — match Apple's first-party voice."*
   "Friendly" is weaker than and partly conflicts with the brief, and none of the
   brief's prohibitions (no exclamation marks, no gamification/celebration) are present.
2. **No register/formality guidance.** `dispatch_prompts.py` `REGIONAL_NOTES` only
   covers spelling/script variants — nothing tells each locale's model whether to use
   du/Sie, tu/vous, です/ます, 해요체, etc. Each locale silently guessed.
3. **No length discipline.** Unlike the metadata template (hard `charLimit` per field),
   the in-app template says nothing about length, so nothing counterbalances verbosity —
   and the warmth instruction being added in Track A could make expansion worse.

Intended outcome: (A) fix the prompt so future and re-done translations are on-tone and
appropriately terse; (B) add a repeatable **semantic audit** sub-pipeline that grades
every locale's strings against the brief and flags problems; (C) re-translate only the
flagged subset through the existing flow. Automated only this round (no human reviewer).

## Approach

Three workstreams. A is the root-cause fix and the rubric the audit grades against, so
it lands first. B is the new audit machinery. C is the targeted fix loop, which reuses
the **existing** translate pipeline unchanged.

Track A's prompt/notes changes are edits inside `scripts/translate_catalog/`. The **new
audit machinery (Track B) lives in its own dedicated folder, `scripts/translate_audit/`,
with its own `README.md`** so future agents can navigate it without untangling it from the
translate pipeline. It mirrors the existing extract → dispatch → fan-out → validate →
report shape and the precedent of `scripts/translate_metadata/audit.py`, and **reuses**
`scripts/translate_catalog/locales.py` and its `REGIONAL_NOTES`/`_GENERIC_NOTE` via import
(no copying) rather than duplicating them.

### Track A — Strengthen the translation prompt + register/cultural notes + length

**Status: ✅ Complete — branch `translations-audit-track-a`.** Verified: `dispatch_prompts.py`
compiles; a synthetic `de`/`ja` render shows the new voice/register/length sub-rules, the
per-locale note (`du` for de, です/ます for ja), and the `enChars` soft budget all composing
correctly. No catalog data changed — existing translations are untouched.

**Modify `scripts/translate_catalog/PROMPT_TEMPLATE.md`** — replace the thin one-line
"Tone" rule (line 21) with a proper voice section ported and adapted from the (richer)
`scripts/translate_metadata/PROMPT_TEMPLATE.md:12-58`, trimmed to UI copy:
- The voice traits: calm / tidy / quietly warm / understated efficient assistant;
  "freshly organized desk, not a finance dashboard."
- The explicit prohibitions from `docs/ux-design-brief.md:14,21`: no exclamation marks,
  no gamification/streaks/trophies, no celebratory or scolding tone, no hype.
- The **register/formality rule** (informal only where modern app copy in that language
  actually uses it; keep polite/formal where the language stays formal regardless of age).
- A short "avoid machine-translation tells" note (don't calque idioms, don't keep English
  sentence rhythm/punctuation).
- **Length discipline (directly addresses the truncation concern).** These are terse UI
  strings (buttons, labels, chips), not prose. Rule: match the source's brevity; prefer
  the **shortest natural phrasing** that preserves meaning *and* tone; **never pad for
  warmth** — warmth comes from word choice, not extra words. Only exceed the English
  length when the target language genuinely requires it (German compounding, Finnish/
  Hungarian agglutination, script width), never as a stylistic default. The source English
  length is provided per key as a **soft budget**, not a hard cap. Placed *after* the tone
  rules so it tempers them.
- Keep **all existing structural rules verbatim** (format specifiers, every key present,
  iCloud/Carry-Over untranslated, JSON-only output). Do not touch those.

**Modify `scripts/translate_catalog/dispatch_prompts.py`** —
- Replace the spelling-only `REGIONAL_NOTES` (lines 47-57) with a richer per-locale note
  dict carrying register + cultural guidance, **ported from
  `translate_metadata/dispatch_prompts.py` `CULTURAL_NOTES` (lines 51-99)** with two
  adaptations: (1) remap storefront codes to catalog codes (`de-DE`→`de`, `fr-FR`→`fr`,
  `es-ES`→`es`, `ar-SA`→`ar`, `nl-NL`→`nl`, `no`→`nb`); keep the spelling guidance already
  present for en-AU/en-CA/en-GB and merge in the rest; (2) strip marketing-only content
  (keyword unbundling, "selling point" positioning) — keep register, formality pronoun,
  and cultural-appropriateness guidance. Add a `_GENERIC_NOTE` fallback (adapted from
  metadata lines 92-99) for any locale without a specific note.
- Surface each key's **English character length** in the composed prompt (the soft budget),
  computed when slicing `source.json` — no change to `extract.py` needed.
- Keep the existing `{REGIONAL_NOTE}` placeholder name so substitution is unchanged.

> This improves the `translate-new-strings` flow too — future new strings will be
> translated on-tone and terse, and the audit (Track B) grades against the same rubric.

**Track A is prompt/notes only — no catalog data changes, so it ships safely on its own**
ahead of the audit. Verification: `python3 -m py_compile dispatch_prompts.py`; run
`extract.py --missing` + `dispatch_prompts.py` on whatever is currently missing (likely
nothing) to confirm the template still composes; eyeball a generated prompt for one
locale to confirm the new sections + length budget render.

### Track B — Audit sub-pipeline (new folder `scripts/translate_audit/`)

**Status: ✅ Complete — branch `translations-audit-track-a`.** Built the dedicated
`scripts/translate_audit/` folder (README + `audit_extract.py` + `AUDIT_PROMPT_TEMPLATE.md` +
`audit_dispatch.py` + `audit_report.py`), the Opus `translation-audit-locale` subagent, and
the `audit-translations` skill. Verified end-to-end on `de`/`ja`: extract pulled 249 keys ×
current translations, dispatch composed per-locale prompts, and the report aggregated a
synthetic finding + the deterministic length filter and wrote a valid re-translation manifest.
Not yet *run* against all 38 locales with real auditor subagents — that's the start of Track C.

Mirrors the translate flow but reads *existing* translations
and produces *findings*. **All Track-B scripts and the audit prompt template live in a
dedicated `scripts/translate_audit/` folder** (kept separate from the translate pipeline
so it's self-contained and discoverable), each path below relative to that folder. The
folder imports `locales.py` and `REGIONAL_NOTES`/`_GENERIC_NOTE` from
`scripts/translate_catalog/` (via a `sys.path` insert) — reuse, not duplication.

0. **`README.md`** (new) — the navigation entry point for the folder: what each script does,
   the run order (`audit_extract` → `audit_dispatch` → fan out `translation-audit-locale`
   subagents → `audit_report`), the `tmp/translate-audit-*` artifact layout, where the
   shared `locales.py`/notes come from, and the char-ratio-is-a-heuristic caveat. Modeled on
   `scripts/translate_catalog/README.md` so the two read consistently.
1. **`audit_extract.py`** (new) — like `extract.py` but emits, per key, English value +
   comment + format specifiers **plus the current translation for each target locale**, to
   `tmp/translate-audit-inputs/audit_source.json`. Reuses catalog-parse logic from
   `translate_catalog/extract.py:57-67`. All 38 locales by default; optional locale filter + `--keys`.
2. **`AUDIT_PROMPT_TEMPLATE.md`** (new) — auditor instructions: the same voice + register +
   **length** rubric as Track A, a `{REGIONAL_NOTE}` slot for the locale's cultural note,
   and the per-locale source block (English + comment + current translation + both char
   lengths). Returns **only flagged strings** as JSON:
   ```json
   { "findings": [ {
       "key": "...", "severity": "high|medium|low",
       "category": "tone|register|cultural|accuracy|grammar|length",
       "current": "<current translation>",
       "back_translation": "<literal English of current>",
       "issue": "<what's wrong vs the rubric>",
       "suggestion": "<improved translation>"
   } ], "locale_summary": "<1-2 sentence overall read>" }
   ```
   Clean strings omitted. For the `length` category the auditor flags a translation as too
   long **only when the extra length is avoidable** (padding/verbosity/needless formality)
   and offers a tighter `suggestion`; it does **not** flag expansion the language
   structurally requires. (That justified-vs-avoidable judgment is what a raw ratio can't make.)
3. **`audit_dispatch.py`** (new) — mirrors `dispatch_prompts.py`: composes one
   `tmp/translate-audit-prompts/{locale}.md` per locale, importing the **same** notes dict
   from Track A (no duplication). Cleans stale prompt/output files by default.
4. **`.claude/agents/translation-audit-locale.md`** (new subagent) — `tools: Read, Write`,
   **`model: opus`** (must out-class the Haiku translator to find its misses). Reads the
   audit prompt, writes findings JSON to `tmp/translate-audit-outputs/{locale}.json`. Same
   narrow "this file only, JSON only" contract as `translation-locale.md`.
5. **`audit_report.py`** (new) — aggregator modeled on `translate_metadata/audit.py`. Loads
   all outputs, prints a triage report grouped by severity then locale (key, category,
   issue, back-translation, suggestion) plus per-locale and global counts. Flags:
   - **Deterministic length pre-filter** — independent of the LLM, compute each
     translation's char length vs English and emit a `length` finding for any string whose
     expansion exceeds `--max-expansion` (default `1.4`). Marks findings `[ratio]`
     (deterministic) or `[llm]` (judged) so it's clear which is which.
   - `--json`; `--min-severity {high,medium,low}`;
   - `--write-manifest` — emit the flagged (locale → keys) set as
     `tmp/translate-inputs/manifest.json` + `source.json` in the **exact shape
     `extract.py --missing` produces**, so Track C reuses the existing flow with no new
     machinery.
   - Exit 0 if no findings at/above threshold, else 1 (so it can gate an autonomous loop).

   **Autonomy note:** dry-run on a single locale (`de`) end-to-end first; if the auditor
   output shape or signal looks wrong, fix the template/report before fanning out to 38,
   and log the adjustment.

### Track C — Triage → targeted re-translation → re-audit

**Status: ✅ Complete (2026-06-03).** Ran the full pipeline across all 38 locales, re-translated
the flagged subset with a stronger model, and re-audited. **84% of flagged pairs cleared.**

Results:
- **Audit (38 locales, 249 keys, Opus auditors).** 2 locales fully clean (`en-AU`, `en-CA`).
  730 findings at/above medium; after excluding 354 advisory `[ratio]` flags, the `[llm]`-judged
  re-translation manifest was **376 (key,locale) pairs across 36 locales, 90 distinct keys**.
  Heaviest: `tr` (27), `pt-PT` (22), `da` (20), `ca` (19), `id` (18).
- **Re-translation (Sonnet override).** All 376 pairs re-translated through the existing
  `translate-new-strings` flow (improved Track A prompt + per-locale register notes), validated
  `--subset` (only benign "identical to English" warnings, all on the protected `Carry-Over`
  term), and merged. `check_translations` + `make build` green.
- **Re-audit (90 keys × 36 locales).** **316/376 pairs cleared (84%).** 60 residuals
  (26 high / 20 medium / 14 low) — but these are dominated by **non-defects** (see decision log):
  ~12 are `feedback.email.subject`, blocked on the **English source** still saying "Budgets app
  feedback"; several are `carryOver` capitalization that correctly mirrors the source's own mixed
  case. The genuine deferred residuals concentrate in the historically-heavy locales (`fr-CA`,
  `el`, `hr`, `ro`). Per the autonomy rule, stopped after one retry — residuals are logged for
  owner review, not looped.

> **Top actionable follow-up — ✅ DONE (2026-06-03):** the audit surfaced that the **English
> source string** `feedback.email.subject` = "Budgets app feedback" still carried the old brand.
> Per owner decision, the source was changed to **"Feedback for Wren"** (`update_keys.py`) and the
> key re-translated across all 38 locales (Sonnet) — clearing the ~12 source-blocked residuals and
> also fixing the pre-existing inconsistency where some locales already said "Wren" and others
> "Budgets". No "Budgets" remains in this key; `check_translations` + `make build` green.

1. `audit_report.py --write-manifest --min-severity medium` → drops the flagged subset
   into `tmp/translate-inputs/`.
2. Run the **existing** `translate-new-strings` flow from Step 2 onward
   (`dispatch_prompts.py` → fan out `translation-locale` subagents → `validate.py --subset`
   → `merge.py`). Two deltas: subagents now read the **improved** template (Track A); and
   **re-translate the flagged strings with a stronger model** (`model: sonnet`/`opus` on
   the dispatches for this round only — these are precisely the strings Haiku got wrong).
3. Re-run the Track-B audit on just the re-translated (locale, key) pairs to confirm the
   findings cleared.
4. `make format && make lint-fix && make build && make test`; commit.

**Autonomy note:** apply judgment on which findings to fix (high+medium by default; low is
advisory). If a re-translation still flags after one retry, leave the original, log it as a
residual item for owner review rather than looping indefinitely.

### Supporting changes

**Status: ✅ Complete — branch `translations-audit-track-a`** (done alongside Track B so the
pipeline is runnable end-to-end).
- **`.claude/settings.json`** — add (additive only) allowlist entries:
  `Bash(python3 scripts/translate_audit/audit_extract.py:*)`, `…/audit_dispatch.py:*`,
  `…/audit_report.py:*`, and `Agent(translation-audit-locale)`. (Never remove/narrow
  existing entries.)
- **`scripts/translate_audit/README.md`** — the folder's navigation doc (created as Track B
  item 0; documents the scripts, flow, artifacts, and the char-ratio caveat).
- **`scripts/translate_catalog/README.md`** — add a short cross-reference pointing to the
  new `scripts/translate_audit/` folder for the quality-audit flow.
- **`.claude/skills/audit-translations/SKILL.md`** (new) — orchestration recipe mirroring
  `translate-new-strings/SKILL.md`, so the fan-out/permissions stay disciplined.

## Layout truncation — what this catches and what it doesn't

**Status: ⏸ Deferred (optional follow-up).** The length rule + ratio flag + auditor
judgment keep translations from gratuitously growing and surface expansion outliers. But
character count is a proxy: whether a string actually truncates depends on the specific
control's width, which we have no per-string budget for. True truncation/clipping is a
UI-level check. Cheapest robust option if wanted later: run the existing UI user-journey
tests (commit `b52ad5a`) under the longest-expanding locale (e.g. `de`) and/or
pseudo-localization, and watch for clipped/wrapped labels. Not part of this round.

## Files

**Modify** — `scripts/translate_catalog/PROMPT_TEMPLATE.md` (A);
`scripts/translate_catalog/dispatch_prompts.py` (A); `.claude/settings.json` (supporting);
`scripts/translate_catalog/README.md` (supporting — add cross-reference).

**Create** — new folder **`scripts/translate_audit/`** containing `README.md`,
`audit_extract.py`, `AUDIT_PROMPT_TEMPLATE.md`, `audit_dispatch.py`, `audit_report.py`;
plus `.claude/agents/translation-audit-locale.md`; `.claude/skills/audit-translations/SKILL.md`.

**Reuse unchanged** — `extract.py`, `validate.py`, `merge.py`, `locales.py`,
`check_translations.py`, the `translation-locale` subagent, and the whole
`translate-new-strings` flow for the fix step.

## Model choices (defaults)
- **Auditor:** Opus — must out-class the Haiku translator to surface its misses.
- **Re-translation of flagged strings:** Sonnet (one-round override). Routine new-string
  translation stays Haiku.

## Out of scope (this round)
- Layout-truncation UI verification (deferred above).
- Human native-speaker review layer (the audit output is structured to hand off later).
- App Store **metadata** translations (already have `translate_metadata/audit.py`).
- Changing the default translation model for routine new-string work.

## Issues & decisions log

_Appended as work proceeds; basis for the end-of-phase summary to the owner._

- **2026-06-02 (Track A):** Kept rule 3 as a single rule with sub-bullets (voice / no-gamify
  / register / length / MT-tells) rather than splitting into new numbered rules, to avoid
  renumbering the structural rules 4–7 and keep the diff minimal. No behavioral downside.
- **2026-06-02 (Track A):** Surfaced the length budget as an `enChars` field injected per
  source entry in `dispatch_prompts.py` (not a new `extract.py` flag), since `dispatch_prompts`
  already has the English value when slicing — smaller change, `extract.py` untouched.
- **2026-06-02 (Track A):** `REGIONAL_NOTES` is now keyed by catalog locale codes; the
  Norwegian note moved from metadata's `no` to this catalog's `nb`. Confirmed all 38
  `locales.py` codes are covered, with `_GENERIC_NOTE` as a safety fallback.
- **2026-06-02 (Track A):** The app has been renamed **Budgets → Wren** (now confirmed by
  owner; the metadata pipeline already used Wren). Updated the brand reference in the catalog
  `PROMPT_TEMPLATE.md` ("called **Wren**") and the `translation-locale` subagent definition,
  and added a rule keeping "Wren" untranslated (it's also the English word for a bird). Scoped
  to this translation-pipeline change only — the app-wide rename (display name, bundle, PRD,
  other docs) is a separate effort, not part of this audit.
- **2026-06-02 (plan, Track B):** Per owner, the Track-B audit scripts will live in their own
  dedicated folder `scripts/translate_audit/` with a `README.md` for future-agent navigation,
  rather than alongside the translate pipeline in `scripts/translate_catalog/`. The new folder
  imports `locales.py` and the register/cultural notes from `translate_catalog/` (reuse, not
  copy). Updated the Approach, Track B, Supporting, and Files sections accordingly.
- **2026-06-02 (Track B):** Did the Supporting changes (settings allowlist, READMEs, skill) in
  the same commit as Track B rather than separately, so the audit pipeline is runnable as a unit.
- **2026-06-02 (Track B):** The dry-run revealed the deterministic length `[ratio]` flag is
  noisy on very short strings (German "Retry"→"Erneut versuchen" is 3.2× but a fine 16-char
  button). Added a `--min-chars` floor (default 20) so the ratio flag focuses on genuinely long
  strings where truncation actually matters; tiny-string ratios are unstable and rarely truncate.
  The LLM auditor still judges length on all strings; `[ratio]` is only the deterministic
  backstop. Even with the floor, German legitimately trips many `[ratio]` flags — expected; the
  Opus auditor's justified-vs-avoidable call (which suppresses the matching `[ratio]`) is the
  real verdict, so do not bulk-re-translate on `[ratio]` alone.
- **2026-06-02 (Track B):** `audit_report.py` exit code is 1 whenever findings exist at/above
  `--min-severity` (including `[ratio]`), so a first full run will "fail" by design — that's the
  gating signal for an autonomous loop, not a build error.
- **2026-06-02 (Track C prep — script audit + permissions):** Hardened the audit scripts for an
  unattended run and closed permission gaps:
  - `audit_report.load_findings` now parses tolerantly (strips ```json fences / surrounding
    prose, falls back to first-`{`…last-`}`) so a single non-conforming subagent output doesn't
    silently drop a locale and force a re-dispatch. Verified against a fenced output.
  - `--write-manifest` now skips + warns on any flagged key absent from `audit_source.json`
    (e.g. an auditor-hallucinated key), so the manifest can't list a key with no source entry.
  - `audit_extract.py` drops keys with no flat English value (plural/`variations`) from
    `audit_source.json` instead of emitting 0-char clutter.
  - `.claude/settings.json`: added `Agent(translation-audit-locale)` (the 38-way auditor
    fan-out would otherwise prompt per locale) and `Skill(audit-translations)`. git/gh/make/
    test were already allowlisted. **Track C can now run without permission prompts.**
  - Orchestration notes for the run (not code): dispatch all auditor subagents in one message
    and have each reply with only a one-line count (findings live in the file) to keep parent
    context lean; run `audit_report.py` standalone (don't `&&`-chain — exit 1 on findings);
    re-translate flagged strings via `translation-locale` with a `model: sonnet`/`opus` override.
- **2026-06-03 (Track C — `de` dry run):** Ran the pipeline end-to-end on German with a live
  Opus `translation-audit-locale` subagent. **No permission prompts** — the allowlist was
  complete, so the full 38-locale wave needs no further settings changes. Auditor signal was
  strong: it caught a real register break (formal "Ihren" in a du-app), a malformed imperative
  ("Nutzen %@" → "Nutze"), a within-flow term inconsistency (Add Funds = "Geldmittel" vs
  "Guthaben"), and a meaning bug ("Bestimmte Daten" reads as *data*, not *dates*) — none
  catchable by a structural gate.
- **2026-06-03 (Track C — manifest is `[llm]`-only):** The dry run confirmed the `[ratio]`
  noise concern at scale: 31 of 45 `de` findings were deterministic ratio flags, almost all
  structurally-justified German compounding (e.g. `Datenschutzerklärung` 1.43×,
  `iCloud-Synchronisierung` flagged *high* at 2.09×). Feeding those into `--write-manifest`
  would re-translate correct strings and risk regressing them. **Fix:** `write_manifest` now
  excludes `source == "ratio"` findings and re-translates only the auditor's `[llm]`-judged
  subset (which already captures genuine, *avoidable* length bloat as `[llm]` `length` findings
  with concrete tighter suggestions). `[ratio]` stays advisory in the human-readable report.
  For `de`/medium this cut the manifest from 24 → 10 keys — exactly the real defects. Updated
  `audit_report.py`, `scripts/translate_audit/README.md`, and the `audit-translations` skill.
- **2026-06-03 (Track C — full 38-locale run):** Audited all 38 locales (Opus), re-translated
  the 376-pair `[llm]` subset with a **Sonnet** override through the existing flow, re-audited.
  84% cleared. Notes for the record:
  - **`validate.py --subset` scope gotcha.** `--subset` only relaxes the *key-set* check; it
    still iterates **all 38 `LOCALES`** unless given an explicit list, so it reported "File
    missing" for the clean locales (`en-AU`/`en-CA`, no re-translation) and stale-key errors on
    their leftover output files. Correct invocation for a subset run is to pass the manifest's
    locale list: `validate.py --subset $(jq -r 'keys|join(" ")' …/manifest.json)`. Also deleted
    two stale `tmp/translate-outputs/{en-AU,en-CA}.json` left from a prior run. (No code change;
    documented here so the next run doesn't misread it as a failure.)
  - **Re-translation model.** Used `model: sonnet` on the `translation-locale` dispatches (the
    plan's default for the fix round) — these are the strings Haiku got wrong. Worked well; no
    structural failures across 36 locales.
- **2026-06-03 (Track C — residuals are mostly non-defects; stopped after one retry):** Of the
  60 residual pairs that still flagged on re-audit:
  - **Source-blocked (~12, the single biggest cluster):** `feedback.email.subject` — the English
    source itself reads "Budgets app feedback". Translators faithfully rendered the stale brand;
    the auditor wants "Wren". **Re-translation cannot fix this** — the *source string* must change
    first. Logged as the top owner follow-up (part of the app-wide rename; out of scope here, and
    a product-copy decision so not made unilaterally). The related `*.email.body.prompt` keys are
    similar.
  - **Source-mirroring (`carryOver` capitalization, ~6):** the English source uses lowercase
    "carry-over" mid-sentence but "Carry-Over" as a label; translations correctly match the source
    case-for-case, and the auditor over-flags the lowercase as a "protected term" violation. Not a
    real defect; the source's own mixed casing is the root.
  - **Genuine deferred (~remainder):** concentrate in the historically-heavy locales (`fr-CA`,
    `el`, `hr`, `ro`) — mostly length/accuracy on accessibility strings and `*.caption.format`.
    Per the autonomy rule ("leave after one retry, log for review, don't loop"), these are left as
    the improved re-translation and flagged for owner review rather than re-run again.
- **2026-06-03 (Consistency + glossary system — follow-on):** Measured cross-key consistency and
  found it unenforced: 31 English strings reused across keys, **190 word-choice divergences** within
  locales (same English, different translation). Built, per owner sign-off:
  - **`consistency_check.py`** (deterministic, `scripts/translate_audit/`) — groups keys by normalized
    English, flags per-locale divergence (`word-choice` vs `casing-only`); `--write-manifest` feeds the
    standard flow. Advisory, not a hard push gate.
  - **Glossary system** (`scripts/translate_catalog/glossary.json` + `glossary_build.py` /
    `glossary_sync.py` + curation/translate prompts + `glossary-locale` Opus agent): canonical per-locale
    translation for recurring terms, **including sub-string terms** ("Add Expense" reuses "Add"+"Expense"),
    with a coherence self-check in the prompt rule. Consulted by `dispatch_prompts.py` **and**
    `audit_dispatch.py` via a shared `{GLOSSARY}` block builder; grown by `glossary_sync.py --detect`
    (auto-add exact repeats, propose the rest). New `consistency` audit category.
  - **Decisions:** glossary growth = auto-add high-confidence + propose rest; divergence fix =
    glossary-guided re-translate (not blind overwrite); scope = Opus-curated focused set; metadata kept
    separate (only the protected-noun invariant is shared). Glossary always built on **Opus**.
  - **Initial glossary:** Opus curated **63 terms** (protected nouns, domain nouns, action verbs, key
    phrases); 38-locale Opus fan-out; all 63 complete across 38 locales; compositional coherence verified
    (de "Add Funds"=`Guthaben hinzufügen` = Funds+Add; fr "Add Expense"=`Ajouter une dépense`).
  - **Agent-registration note:** the new `glossary-locale` agent isn't picked up mid-session, so this run
    used `general-purpose` with a `model: opus` override (same model). The `glossary-locale.md` definition
    is correct and will be used by future sessions; scripts/skills/settings all reference it.
