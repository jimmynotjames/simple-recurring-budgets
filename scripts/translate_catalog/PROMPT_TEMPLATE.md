# Translation Task — {LOCALE_NAME} ({LOCALE_CODE})

You are translating the UI strings for a native iOS budgeting app called **Budgets** from English into **{LOCALE_NAME}**.

## Your task

Translate every string in the source JSON below into **{LOCALE_NAME}** ({LOCALE_CODE}).
Return a **single JSON object** (no markdown fences, no prose, no commentary) where each key maps to its translated string.

## Rules — read carefully

1. **Preserve every format specifier exactly.**
   - `%@` is a generic placeholder (replaced at runtime by a name, amount, date, etc.)
   - `%1$@`, `%2$@`, `%3$@` are positional placeholders (first argument, second argument, third argument)
   - `%lld` is an integer count
   - The **count and form** of specifiers MUST match the source exactly.
   - Their **order** MAY change if the grammar of {LOCALE_NAME} requires it (e.g. `%1$@, %2$@` may become `%2$@, %1$@`).

2. **Use the `comment` field for context.** It explains where the string appears and what it means. A short label like "Cancel" is a dismiss button, not "cancel a subscription".

3. **Tone:** Friendly, concise, natural UI copy — match Apple's first-party iOS app voice for {LOCALE_NAME}. Do not add punctuation that would look odd in Apple UI (e.g. avoid trailing periods on short button labels).

4. **Numbers, currencies, and dates** are handled by `FormatStyle` at runtime. Do not translate or alter the format specifiers — just keep them verbatim.

5. **"iCloud"**, **"Carry-Over"** (as a product concept), and any proper nouns that Apple does not translate in their own UI should be left in English.

6. **Every key in the input MUST appear in your output.** If a string is genuinely untranslatable (rare), copy the English verbatim and add a separate `"<key>__note"` sibling entry explaining why.

7. **Output only the JSON object.** Do not wrap it in markdown fences. Do not add any prose before or after it.

{REGIONAL_NOTE}

## Source strings

```json
{SOURCE_JSON}
```
