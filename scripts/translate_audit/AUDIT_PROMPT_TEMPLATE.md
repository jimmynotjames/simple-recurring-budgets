# Translation audit — {LOCALE_NAME} ({LOCALE_CODE})

You are a senior **native {LOCALE_NAME}** reviewer auditing the existing UI strings of {AUDIT_APP_LINE} The strings were machine-translated from English. Judge their quality; don't re-translate everything. **Report only strings with a real problem, and omit the ones that are fine.**

## Rubric

**Voice.** {AUDIT_VOICE}

**Register.** The voice is modern and respectful: current and unfussy, never stiff or old-fashioned, and never so casual that it would sound flippant to an older reader. The regional note below sets this locale's form of address; grade against the note, not your own preference. The wrong register is a real problem: forced informality where the note sets the polite form reads as rude, not friendly, and vice versa. Check that the address is consistent across the locale, especially in error messages, Settings footers and VoiceOver hints, where the other form most often creeps in. Short button and menu labels are exempt: a label in the glossary's form, or the platform's usual label form (often an infinitive or bare verb), is not a register error. If you believe the note itself is wrong for {LOCALE_NAME}, say so once in `locale_summary` rather than flagging strings that follow it.

**Length.** These are terse strings in tight layouts. `enChars` is the English length and `currentChars` the translation's. Flag a translation as too long only when the extra length is avoidable (padding, verbosity, needless formality), never when {LOCALE_NAME} structurally needs it (compounding, agglutination, script width).

**Accuracy and mechanics.** The translation keeps the English meaning (the `comment` gives context). Format specifiers (`%@`, `%lld`, `%1$@`, …) keep the same count and form, though their order may change for grammar; a dropped or added specifier is high severity. No grammar or spelling errors. {AUDIT_BRAND}

<!-- if sample -->
{AUDIT_SAMPLE}

<!-- end sample -->
<!-- if plural -->
**Plurals.** Entries with `englishPlural` (the English per-category forms) and `currentPlural` (the translation's category → string map) are count-dependent. Grade: (1) the right CLDR categories for {LOCALE_NAME}, which may be more than English's one/other (Russian needs `one`/`few`/`many`/`other`); a missing required category, or English's two forms copied, is a real bug (`category: accuracy`, often high); (2) grammar and agreement in each category; (3) `%lld` kept in every form. Put the per-category fix in `suggestion`, as a small object or readable text.

<!-- end plural -->
## Regional note for {LOCALE_NAME}

{REGIONAL_NOTE}

<!-- if glossary -->
## Glossary: agreed {LOCALE_NAME} terms

Flag (`category: consistency`) a string that renders one of these terms differently (a synonym, a different inflection) without a good contextual reason, including a term inside a longer string {GLOSSARY_INLINE_EXAMPLE}. Use the glossary rendering as the `suggestion`. Don't flag a deviation the string genuinely needs to read naturally. Entries are listed in standalone-label casing; a term capitalized mid-sentence where {LOCALE_NAME} would lowercase it is a finding too.

{GLOSSARY}
<!-- end glossary -->

## Output

One JSON object, with no fences and no prose; an empty `findings` array if every string is fine:

```json
{
  "findings": [
    {
      "key": "<the key>",
      "severity": "high | medium | low",
      "category": "tone | register | cultural | accuracy | grammar | length | consistency",
      "current": "<the current translation, verbatim>",
      "back_translation": "<a literal English back-translation of the current translation>",
      "issue": "<what is wrong, and which rule it breaks>",
      "suggestion": "<an improved translation that obeys the rubric and is no longer than necessary>"
    }
  ],
  "locale_summary": "<1-2 sentences on the overall quality for this locale>"
}
```

Severity: **high** is a wrong or misleading meaning, a dropped or added format specifier, or a clearly wrong register (rude or jarringly formal); **medium** is clearly off-tone, avoidably too long, or awkward; **low** is minor polish on an acceptable string. `back_translation` is required so a non-speaker can see the problem.

## Source strings (English and current {LOCALE_NAME})

```json
{SOURCE_JSON}
```
