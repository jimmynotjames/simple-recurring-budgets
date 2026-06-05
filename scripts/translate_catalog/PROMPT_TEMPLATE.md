# Translation Task — {LOCALE_NAME} ({LOCALE_CODE})

You are translating the UI strings for a native iOS budgeting app called **Wren** from English into **{LOCALE_NAME}**.

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

3. **Voice, tone, register & length.** Match Apple's first-party iOS app voice for {LOCALE_NAME}, rendered in *this* app's specific character. Carry the personality into {LOCALE_NAME} the way it's naturally expressed there — the trait stays constant, its expression is localized.

   - **The voice is calm, tidy, quietly warm, and understated** — an efficient assistant; "a freshly organized desk," not a finance dashboard. A little quiet warmth is welcome; hype is not. **No exclamation marks**, no ALL-CAPS, no salesy superlatives, and **no celebratory or congratulatory tone** over routine actions (logging an expense, finishing setup). Warmth comes from word choice, never from extra words or punctuation.
   - **Never gamify or scold.** No streak / trophy / "great job!" framing, and no guilt or alarm about money. Progress and remaining-balance copy is calm, never scolding.
   - **Register / formality.** Use the informal address **only if** modern, youth-oriented consumer-app copy in {LOCALE_NAME} actually uses it (e.g. French/German fintech aimed at younger users uses "tu" / "du"). If this language keeps the polite/formal address in app copy **regardless of audience age** (e.g. Hindi "आप", Japanese です/ます, Korean 해요체, Thai polite particles), keep the polite form — forced informality reads as wrong, not friendly. The regional note below gives the specific choice for this locale; follow it.
   - **Stay concise — match the source's length.** These are terse UI strings (buttons, labels, chips, short sentences) shown in tight layouts. Each source entry lists its English character length as `enChars`: treat it as a **soft budget** and aim for a translation of similar length. Prefer the **shortest natural phrasing** that preserves the meaning *and* the tone. **Do not pad for warmth or politeness.** Run meaningfully longer than the English **only** when the structure of {LOCALE_NAME} genuinely requires it (compounding, agglutination, script width) — never as a stylistic choice. A tight, plain rendering beats a longer, fancier one.
   - **No odd punctuation, no MT tells.** Don't add punctuation that looks wrong in Apple UI (e.g. trailing periods on short button labels); use this language's normal conventions, not English ones. Don't calque English idioms word-for-word — render the *idea* in a natural {LOCALE_NAME} idiom — and don't preserve English sentence rhythm or clause order where restructuring reads more naturally.

4. **Numbers, currencies, and dates** are handled by `FormatStyle` at runtime. Do not translate or alter the format specifiers — just keep them verbatim.

5. **"Wren"** (the app's name) must be kept exactly as "Wren" — never translate or transliterate it, even though it is also an English word for a small bird. **"iCloud"** and any proper nouns that Apple does not translate in their own UI should likewise be left in English. (Domain nouns like "Carry-Over" are **not** protected — translate them per the glossary.)

6. **Use the glossary for consistency.** If a **Glossary** section appears below, it lists app terms that already have an agreed {LOCALE_NAME} translation. When a source string contains one of these terms, render that term using the glossary's translation so it reads **identically everywhere** in the app. The glossary applies to **parts** of a string too: for "Add Expense", reuse the glossary's "Add" and "Expense". **Coherence wins, though** — after composing, re-read your full translation; if mechanically stitching the glossary terms together is awkward or ungrammatical in {LOCALE_NAME}, write the natural rendering instead while keeping the key terms recognizable. If the *whole* source string is itself a glossary term, use that entry directly. (No Glossary section = no pinned terms for these strings.)

7. **Plurals.** Most entries have a `"value"` string — translate it normally and map the key to a single translated string. But an entry with a **`"plural"`** object instead (e.g. `{"one": "%lld logged expense", "other": "%lld logged expenses"}`) is a count-dependent string. For those keys:
   - Map the key to a **JSON object of CLDR plural categories** → translated strings, e.g. `"key": {"one": "…", "other": "…"}`.
   - Use the categories **{LOCALE_NAME} actually needs** — not necessarily the same ones as English. Many languages need more (e.g. `one`/`few`/`many`/`other`) or fewer (`other` only). Always include **`other`**. Valid categories: `zero`, `one`, `two`, `few`, `many`, `other`.
   - Keep the count format specifier (`%lld`) in **every** category form.
   - Get the grammar right for each category (the number that replaces `%lld`, agreement, word endings).

8. **Every key in the input MUST appear in your output.** If a string is genuinely untranslatable (rare), copy the English verbatim and add a separate `"<key>__note"` sibling entry explaining why.

9. **Output only the JSON object.** Do not wrap it in markdown fences. Do not add any prose before or after it.

{REGIONAL_NOTE}

{GLOSSARY}

## Source strings

```json
{SOURCE_JSON}
```
