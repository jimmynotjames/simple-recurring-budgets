# Transcreation task — {SAMPLE_SUBJECT} for {LOCALE_NAME} ({LOCALE_CODE})

{SAMPLE_INTRO}

This is **transcreation, not translation**. The test for every item: *would a person living where {LOCALE_NAME} is spoken actually write this on their own list?* If not, replace it with what they would write.

## Rules

1. **Make every item culturally native.**
{SAMPLE_ITEMS_RULE}
2. **The structure is fixed.** Every input key maps to exactly one output string. Don't merge, split, add, or drop items; the count, the order, and which items read as "done" in the screenshots are fixed by the keys. A note (`*.notes` key) stays a note for the same item; adapt it to match your item.
3. **Keep names short.** These are rows in a narrow phone list, and a long name wraps onto extra lines. `enChars` is the English length: a soft budget. Prefer the shortest natural phrasing; a name that wraps is worse than one that loses a detail. Notes may run a little longer.
4. **Use the `comment` field** for what the item is and which list it belongs to.
5. **Voice.** Plain, friendly, everyday: the way a real person writes a list for themselves. Nobody is being addressed, so no form of address applies here: write items the way people in {LOCALE_NAME} write notes to self (bare nouns, or whichever infinitive or imperative form natives use on their own lists), never a polite address to a reader. The regional note still governs script, vocabulary and dialect. No marketing tone, no exclamation marks.
6. **Protected names.** {PROTECTED_QUOTED} stay verbatim if they appear; Apple product names stay as Apple writes them in {LOCALE_NAME}. Keep any format specifier (`%@`, `%lld`) exactly.
7. **If a string is genuinely impossible to adapt,** copy the English and add a `"<key>__note"` sibling saying why.

## Regional note for {LOCALE_NAME}

{REGIONAL_NOTE}

<!-- if glossary -->
## Glossary: agreed {LOCALE_NAME} terms

Where a demo item uses one of these app terms, render it with the agreed translation.

{GLOSSARY}
<!-- end glossary -->

## Output

One JSON object mapping every input key to its {LOCALE_NAME} string, with no fences and no prose.

## Source strings

```json
{SOURCE_JSON}
```
