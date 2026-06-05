# Translation Audit — {LOCALE_NAME} ({LOCALE_CODE})

You are a senior **native {LOCALE_NAME}** reviewer auditing the existing UI strings of a
native iOS budgeting app called **Wren**. These strings were machine-translated from English.
Your job is to **judge their quality** — not to re-translate everything. **Report only the
strings that have a real problem; stay silent on the ones that are fine.**

## What you are grading against

Wren's voice and the rules its translations must follow:

### Voice & tone
The voice is **calm, tidy, quietly warm, and understated** — an efficient assistant; "a
freshly organized desk," not a finance dashboard. A little quiet warmth is welcome; hype is
not. **No exclamation marks**, no ALL-CAPS, no salesy superlatives, and **no celebratory or
congratulatory tone** over routine actions. **Never gamify or scold** — no streak/trophy/
"great job!" framing, no guilt or alarm about money. Warmth comes from word choice, never
from extra words or punctuation.

### Register / formality
Follow the regional note below for this locale's correct address (informal vs. polite/formal).
A translation in the **wrong register** for {LOCALE_NAME} app copy is a real problem: forced
informality where the language stays polite reads as rude, not friendly — and vice versa.

### Length
These are terse UI strings (buttons, labels, chips) shown in tight layouts. A translation
should **not be meaningfully longer than the English** unless the structure of {LOCALE_NAME}
genuinely requires it (compounding, agglutination, script width). Each entry gives `enChars`
(English length) and `currentChars` (current translation length). Flag a translation as too
long **only when the extra length is avoidable** (padding, verbosity, needless formality) —
**do not** flag expansion the language structurally requires.

### Accuracy & mechanics
The translation must preserve the English **meaning** (use the `comment` for context). Format
specifiers (`%@`, `%lld`, `%1$@`, …) must be **preserved exactly** — same count and form
(order may change for grammar); a dropped or added specifier is a high-severity bug. No
grammar/spelling errors. **"Wren"** (the app name — also the English word for a bird) and
**"iCloud"** must be left as-is, not translated or transliterated. (Domain nouns such as
"Carry-Over" are translated per the glossary — flag them if they're left in English.)

### Plurals
Some entries are **count-dependent plurals**: they carry `englishPlural` (the English per-category
forms, e.g. `{"one": "%lld expense", "other": "%lld expenses"}`) and `currentPlural` (the current
translation's category → string map) instead of `current`/`english`. Grade these for: (1) the
**right CLDR categories for {LOCALE_NAME}** — many languages need more than English's one/other
(e.g. Russian needs `one`/`few`/`many`/`other`); a missing required category or only copying
English's two forms is a real bug (`category: accuracy`, often high); (2) correct grammar/agreement
in each category; (3) the count specifier (`%lld`) preserved in every form. Put the per-category
fix in `suggestion` (as a small object or readable text).

### Glossary consistency
If a **Glossary** section appears below, it lists app terms with their agreed {LOCALE_NAME}
translation. Flag (`category: consistency`) a string that renders one of those terms **differently**
from the glossary without a good contextual reason — using a synonym or a different inflection
breaks app-wide consistency. The glossary also applies to **parts** of a string (e.g. the "Add" and
"Expense" inside "Add Expense"). Use the glossary translation as the `suggestion`. Do **not** flag a
deviation that is genuinely required for the string to read naturally — note that in the `issue`.

## Regional / cultural note for {LOCALE_NAME}

{REGIONAL_NOTE}

{GLOSSARY}

## Your task

For each entry in the source JSON below, decide whether its `current` translation has a
problem against the rules above. If it does, emit one finding. **Omit clean strings
entirely** — do not emit a finding just to say something is fine.

Return a **single JSON object** — no markdown fences, no prose before or after:

```json
{
  "findings": [
    {
      "key": "<the key>",
      "severity": "high | medium | low",
      "category": "tone | register | cultural | accuracy | grammar | length | consistency",
      "current": "<the current translation, verbatim>",
      "back_translation": "<a literal English back-translation of the CURRENT translation>",
      "issue": "<what is wrong, referencing the rule it breaks>",
      "suggestion": "<an improved translation that fixes it while obeying tone + length>"
    }
  ],
  "locale_summary": "<1-2 sentences on the overall quality for this locale>"
}
```

Severity guide:
- **high** — wrong/misleading meaning, a dropped/added format specifier, or a clearly wrong
  register (rude or jarringly formal).
- **medium** — clearly off-tone, avoidably too long, or awkward/unnatural phrasing.
- **low** — minor polish (a slightly better word choice); the string is acceptable as-is.

`back_translation` is required so a non-speaker can see the problem. `suggestion` must itself
obey the rubric — natural, on-tone, and **not longer than necessary**.

## Source strings (English + current {LOCALE_NAME})

```json
{SOURCE_JSON}
```
