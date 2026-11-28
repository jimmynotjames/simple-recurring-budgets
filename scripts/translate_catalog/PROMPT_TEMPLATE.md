# Translation task — {LOCALE_NAME} ({LOCALE_CODE})

{UI_INTRO}

## Rules

1. **Format specifiers.** `%@` is a runtime value (a name, a date), `%1$@` and `%2$@` are positional, `%lld` is an integer count. Keep every specifier verbatim, in the same count and form as the source; their order may change if {LOCALE_NAME} grammar needs it (`%1$@, %2$@` → `%2$@, %1$@`). To reorder two plain `%@`, number them by their source order (`%@ … %@` → `%2$@ … %1$@`); that is the only change of form allowed. Numbers and dates are formatted at runtime.
2. **Context.** Each entry's `comment` says where the string appears and what it means. A short label like "Cancel" is a dismiss button, not "cancel a subscription".
3. **Voice.** {UI_VOICE}
4. **Register.** Use the form of address set below, in every string, including error messages, Settings footers and VoiceOver hints; system text is where the other form most often creeps in. Short button and menu labels are the exception: they take the glossary's form, or the platform's usual label form (often an infinitive or bare verb), whatever the address. Get warmth from word choice and brevity, never from changing the address.
5. **Length.** These are terse strings in tight layouts. `enChars` is the English length: treat it as a soft budget. Use the shortest natural phrasing that keeps the meaning and the tone, and don't pad for warmth or politeness. Run longer only where {LOCALE_NAME} structurally needs it (compounding, agglutination, script width).
6. **Native, not translated.** Use this language's punctuation conventions, not English ones (no trailing period on a short button label). Render the idea in a natural idiom rather than a word-for-word calque, and restructure English clause order where that reads better.
7. **Protected names.** {UI_PROTECTED_RULE}
8. **Every input key appears in the output.** If a string is genuinely untranslatable (rare), copy the English and add a `"<key>__note"` sibling saying why.

<!-- if plural -->
## Plurals

An entry with a `plural` object instead of `value` is count-dependent. Map its key to a JSON object of CLDR categories → strings, e.g. `"key": {"one": "…", "other": "…"}`.
- If the entry has `requiredPluralCategories`, produce **exactly** those categories, no fewer and no extra: it is the authoritative CLDR set {LOCALE_NAME} needs for integer counts. Without the list, use the categories {LOCALE_NAME} needs, which may differ from English. Always include `other`. Valid: `zero`, `one`, `two`, `few`, `many`, `other`.
- Keep `%lld` in every category, and get each category's grammar right (agreement, word endings).
<!-- end plural -->

## Regional note for {LOCALE_NAME}

<!-- if register -->
**Form of address:** {REGISTER}.

<!-- end register -->
{REGIONAL_NOTE}

<!-- if glossary -->
## Glossary: agreed {LOCALE_NAME} terms

Render these terms exactly as listed so they read identically across the app, including inside a longer string: {GLOSSARY_COMPOSE_EXAMPLE}. If the whole string is a glossary term, use that entry. Entries are listed in standalone-label casing: inside a sentence or a sentence-case label, case them the way {LOCALE_NAME} does there (a common noun stays lowercase mid-sentence), and copy an English Title Case only where {LOCALE_NAME} UI uses title case too. Coherence wins: if stitching terms together reads awkwardly or ungrammatically, write the natural rendering and keep the key terms recognizable.

{GLOSSARY}
<!-- end glossary -->

## Output

One JSON object mapping each key to its translation (a string, or a category object for a plural), with no fences and no prose.

## Source strings

```json
{SOURCE_JSON}
```
