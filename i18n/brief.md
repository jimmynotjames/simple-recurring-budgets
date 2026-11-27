# Wren localization brief

App-specific prose for the shared prompt templates under scripts/translate_*/. Each fragment
fills the template placeholder of the same name; scripts/translate_catalog/app_config.py loads
them. A fragment may use the template's own placeholders ({LOCALE_NAME}) and {APP_NAME}.

## translate_catalog/PROMPT_TEMPLATE.md

<!-- fragment UI_INTRO -->
Translate the UI strings of **Wren**, a native iOS budgeting app, from English into **{LOCALE_NAME}**. Wren is fast, everyday expense and budget tracking: set a few spending limits, log what you spend in seconds, and see what's left. It is a calm utility, not a finance dashboard.
<!-- end UI_INTRO -->

<!-- fragment UI_VOICE -->
Match Apple's first-party iOS voice for {LOCALE_NAME}, carrying this app's character: calm, tidy, quietly warm and understated; an efficient assistant, "a freshly organized desk", not a finance dashboard. The traits stay constant; express them the way {LOCALE_NAME} naturally does. A little quiet warmth is welcome, hype is not, and warmth comes from word choice, never from extra words or punctuation. No exclamation marks, no ALL-CAPS, no salesy superlatives, no celebrating routine actions (logging an expense, finishing setup). Never gamify or scold: no streak, trophy or "great job!" framing, and no guilt or alarm about money; progress and remaining-balance copy stays calm.
<!-- end UI_VOICE -->

<!-- fragment UI_PROTECTED_RULE -->
"Wren" (the app's name) stays exactly "Wren": never translated or transliterated, even though it is also an English word for a small bird. Leave "iCloud" and other proper nouns Apple keeps in English in its own UI. Domain nouns like "Carry-Over" and "Expense" are not protected; translate them.
<!-- end UI_PROTECTED_RULE -->

<!-- fragment GLOSSARY_COMPOSE_EXAMPLE -->
for "Add Expense", reuse "Add" and "Expense"
<!-- end GLOSSARY_COMPOSE_EXAMPLE -->

## translate_catalog/GLOSSARY_TRANSLATE_PROMPT.md

<!-- fragment GLOSSARY_APP_LINE -->
**Wren**, a native iOS budgeting app.
<!-- end GLOSSARY_APP_LINE -->

<!-- fragment GLOSSARY_COMPOSE_RULE -->
Many terms combine ("Add" + "Expense" → "Add Expense")
<!-- end GLOSSARY_COMPOSE_RULE -->

<!-- fragment GLOSSARY_VOICE -->
Wren's voice is calm, tidy, quietly warm, understated — no hype,
   no exclamation marks.
<!-- end GLOSSARY_VOICE -->

<!-- fragment GLOSSARY_PROTECTED_EXAMPLE -->
(e.g. "Wren" stays "Wren", "iCloud" stays "iCloud")
<!-- end GLOSSARY_PROTECTED_EXAMPLE -->

<!-- fragment GLOSSARY_OUTPUT_EXAMPLE -->
{ "Add Funds": "<translation>", "Add": "<translation>", "Budget": "<translation>", "Wren": "Wren" }
<!-- end GLOSSARY_OUTPUT_EXAMPLE -->

## translate_catalog/GLOSSARY_CURATION_PROMPT.md

<!-- fragment CURATION_INTRO -->
# Glossary curation — pick the canonical term set for Wren

You are a senior localization architect for **Wren**, a native iOS budgeting app. Before the
app's UI strings are translated into 49 languages, we want a **glossary**: a focused set of
recurring terms that must translate **consistently** everywhere they appear, so two buttons
that both say "Add Expense" never drift apart, and so a compound like "Add Expense" can reuse
the agreed translations of "Add" and "Expense".
<!-- end CURATION_INTRO -->

<!-- fragment CURATION_INCLUDE -->
- **Exact repeated strings** — any English string used under more than one key (e.g. "Cancel",
  "Save", "Add Funds", "Current Period", "Delete Expense", "Past Periods"). These must be identical
  wherever they appear. Include essentially all of these.
- **Core domain nouns** — the app's vocabulary: "Budget", "Expense", "Period", "Carry-Over",
  "Funds", "Balance", "Allocation", etc. These should read the same in every screen.
- **High-frequency action verbs** that pair with those nouns — "Add", "Edit", "Delete", "Reset",
  "Resume", "Save" — so compounds ("Add Expense", "Edit Budget", "Delete Budget") compose from a
  stable base.
- **Recurring modifier/field words** — "Start date", "End date", "Today", "When", "Settings".
<!-- end CURATION_INCLUDE -->

<!-- fragment CURATION_EXCLUDE -->
**Exclude**: full sentences, accessibility hints, one-off phrasings, and generic connective words
that don't carry app meaning. Aim for a **focused set (~40–70 terms)**, not every token. Quality and
reusability over coverage. Prefer the shortest meaningful term: pin "Add" and "Expense" as well as
the phrase "Add Expense" only if the phrase itself recurs and benefits from a single canonical form.
<!-- end CURATION_EXCLUDE -->

<!-- fragment CURATION_PROTECTED -->
These are **never translated** — include them as terms so downstream steps lock them, with context
noting they stay verbatim: see `protected` in the candidates JSON (e.g. **Wren**, **iCloud**).
(Domain nouns such as **Carry-Over** are ordinary glossary terms — translate them per locale; they
are not protected.)
<!-- end CURATION_PROTECTED -->

<!-- fragment CURATION_OUTPUT_EXAMPLE -->
    {
      "en": "Add Funds",
      "context": "Title/button for the 'add funds' mode of the add-expense screen — putting money into a budget, the opposite of logging a spend.",
      "partOfSpeech": "verb phrase",
      "sourceKeys": ["..."]
    },
    {
      "en": "Biweekly",
      "context": "Budget period that resets once every two weeks (fortnightly), never twice a week. False-cognate trap: French 'bimensuel' means twice a month.",
      "partOfSpeech": "adjective",
      "sourceKeys": ["..."]
    }
<!-- end CURATION_OUTPUT_EXAMPLE -->

<!-- fragment CURATION_CONTEXT_EXAMPLE -->
(e.g. "Cancel" = dismiss
  a sheet, not cancel a subscription; "Biweekly" = every two weeks, not twice a week)
<!-- end CURATION_CONTEXT_EXAMPLE -->

## translate_audit/AUDIT_PROMPT_TEMPLATE.md

<!-- fragment AUDIT_APP_LINE -->
**Wren**, a native iOS budgeting app for fast, everyday expense tracking.
<!-- end AUDIT_APP_LINE -->

<!-- fragment AUDIT_VOICE -->
Calm, tidy, quietly warm and understated: an efficient assistant, "a freshly organized desk", not a finance dashboard. A little quiet warmth is welcome, hype is not, and warmth comes from word choice, never from extra words or punctuation. No exclamation marks, no ALL-CAPS, no salesy superlatives, no celebrating routine actions. Never gamify or scold: no streak, trophy or "great job!" framing, no guilt or alarm about money.
<!-- end AUDIT_VOICE -->

<!-- fragment AUDIT_BRAND -->
"Wren" (the app's name, also the English word for a bird) and "iCloud" stay as-is: not translated, transliterated, or re-cased. Domain nouns such as "Carry-Over" are translated; flag one left in English.
<!-- end AUDIT_BRAND -->

<!-- fragment GLOSSARY_INLINE_EXAMPLE -->
(the "Add" in "Add Expense")
<!-- end GLOSSARY_INLINE_EXAMPLE -->

## translate_metadata/PROMPT_TEMPLATE.md

<!-- fragment STORE_APP_LINE -->
**Wren**, a native iOS app for **fast, everyday expense and budget tracking**.
<!-- end STORE_APP_LINE -->

<!-- fragment STORE_VOICE -->
Wren is "the easiest, fastest way to track everyday spending": not a personal-finance suite, not a banking app, not a business-expense tool. The voice is a **calm, tidy, quietly warm, efficient assistant**: a freshly organized desk, not a finance dashboard.

- **First-person singular.** Write as "I", not "we": one independent developer builds this app, and the voice should feel personal and direct ("I built Wren to…"). Where first-person singular is jarring in this market's app marketing, use what is natural there (an impersonal construction, the brand as subject, second-person framing); the goal is warmth, not a forced "I".
- **Calm and understated:** confident and plain, never hype; no exclamation marks, ALL-CAPS, or salesy superlatives ("the best", "amazing", "revolutionary").
- **Warm, not cute:** no gamification, streaks or trophies, no pressure to "save more", no guilt about spending. Wren helps you *see* your money; it doesn't scold or cheerlead.
- **Light and quick:** short, scannable sentences; the product is fast, so the copy should feel fast. Lead with the benefit (track in seconds, see what's left), not the mechanism.
- **Trustworthy and private:** privacy is a quiet point of pride (iCloud sync, no servers, no bank logins); state it plainly, don't oversell it.
<!-- end STORE_VOICE -->

<!-- fragment STORE_BRIEF -->
1. **Foresight: "know what you can spend, before you spend it."** See what's left at a glance, in the moment, so you decide *before* you spend, not after. The hero message, and the hook the roomier fields open on.
2. **Speed and simplicity of logging:** add an expense in one tap, in seconds; logging, not filling out a form. The #1 differentiator against heavyweight apps; keep it close behind the foresight hook.
3. **Effortless setup and scope:** no bank logins, no spreadsheets, no setup marathon. Built for everyday, recurring spending in daily, weekly, biweekly or monthly limits, not your whole financial life.
4. **Carry-Over:** unspent money rolls forward, so what you save today rolls into tomorrow. Wren's distinctive mechanic; keep it, don't cut it as filler.
5. **Calm, elegant, glanceable:** a tidy ledger, not a busy dashboard; no charts for charts' sake.
6. **Private:** two facets, each its own feature bullet in the source: iCloud sync across your devices, and data kept on-device and in iCloud only (no third-party servers, no bank integration). A weak selling point in some markets; defer to the market note where it says so.
<!-- end STORE_BRIEF -->

<!-- fragment STORE_NOT -->
**Wren is not** (never imply it): a business or travel expense tool, or a tax or receipt logger; a whole-life personal-finance or master-budgeting suite; bank- or card-integrated (no account linking, no transaction import); a charts-and-graphs analytics dashboard.
<!-- end STORE_NOT -->

<!-- fragment STORE_SCREENSHOTS -->
**The three screenshots beside the text are already said:** the budgets overview (everyday categories such as "Coffee/Tea", "Food", "Clothes" on daily and weekly periods, the "see what's left" feeling), adding an expense with a Recents section (the speed of logging), and one budget's detail over its period. Don't spend scarce characters re-describing them unless the point is worth landing in both words and pictures (the foresight hero and fast logging are); stress what a picture can't convey, like the feel, the privacy stance, the carry-over payoff and the anti-positioning. This picks which existing copy to emphasize; it is not license to add claims, bullets or lines the English doesn't have.
<!-- end STORE_SCREENSHOTS -->

<!-- fragment STORE_BRAND_RULE -->
1. **Brand.** "Wren" is the product's name: never translate, transliterate, explain, or gloss it (no "(a small bird)"), and never mention birds; carry the light, quick, nimble feeling instead. Its casing is fixed (initial capital only, never "WREN" or "wren"), even in a header, for emphasis, or against local title-casing.
<!-- end STORE_BRAND_RULE -->

<!-- fragment STORE_APPLE_TERMS -->
5. **Apple terms.** Leave "iCloud" and other proper nouns Apple keeps in English in its own UI. Domain words like "budget" and "Carry-Over" (a Wren product concept, not a protected name) are not protected: translate them, using the agreed term below wherever one is given.
<!-- end STORE_APPLE_TERMS -->

<!-- fragment STORE_EXTRA_RULES -->
7. **"Biweekly" means every two weeks (fortnightly), never twice a week.** In the source it always names a budget period that resets once every two weeks. Several languages have a false-cognate trap (French *bimensuel* means twice a *month*, and a literal "bi-weekly" can read as twice a week): use the unambiguous local term, and the agreed term below where one is given.
8. **Untranslatable English idioms.** "Make every day more easeful", "stay on top of your money", "setup marathon": render the idea in native idiom, never word for word. "Easeful" especially is a soft, slightly poetic English word with no literal equivalent in most languages; carry the feeling of an easier, lighter day rather than hunting for a one-word match.
<!-- end STORE_EXTRA_RULES -->

<!-- fragment STORE_GLOSSARY -->
The app's own {LOCALE_NAME} interface names its core concepts with these words. Someone who reads the listing and then opens the app must meet the same words, so these renderings override your own preference, a more searchable synonym, and any loanword hint in the market note:

{GLOSSARY}

- **Use the agreed word for every mention** in `name`, `subtitle`, `promotional_text`, `description` and `release_notes`, in whatever plural, case, article or compound form the sentence needs, and in this language's casing (a common noun stays lowercase mid-sentence, whatever the label casing above). A different word or synonym is wrong, and so is swapping between the local word and the English loanword (in either direction).
- **A shorter form only where this language would naturally use one.** In a longer field, a later mention may shorten an agreed term, but only when native copy here really does that and the meaning stays unmistakable. Never shorten in `name` or `subtitle`, and never shorten to a different word.
- **The core nouns must be searchable.** Put the base form of the agreed word for "Budget" and "Expense" in `keywords` unless `name` or `subtitle` already has that exact form (the Keywords section's same-form rule). A common English loanword such as "budget" may also appear as an extra search term, but never in place of the agreed word.
<!-- end STORE_GLOSSARY -->

<!-- fragment STORE_NAME_DESCRIPTOR -->
the descriptor names the category (an expense or spending tracker) so the listing is findable.
<!-- end STORE_NAME_DESCRIPTOR -->

<!-- fragment STORE_SUBTITLE -->
It sits directly under the app name (the `name` you write, or **{STORE_NAME}** if you are not writing one), so don't repeat the name's words. The 30-character `subtitle` is tight: a clean, punchy line that fits beats a literal one that doesn't. The foresight hero ("know what you can spend") is hard to fit in 30 characters, so lead with the **everyday, fast and easy budgeting benefit**, as the English does, and keep the foresight hook for `promotional_text` and `description`. Don't let the line drift to a lower-priority benefit just because it translates more neatly. People read it and search indexes it, so it must work as both.
<!-- end STORE_SUBTITLE -->

<!-- fragment STORE_KEYWORD_DOMAIN -->
`keywords` are search terms, not prose: what a native {LOCALE_NAME} user would type to find a budgeting or expense-tracking app. Comma-separated, **no spaces after commas**, deduplicated; singular forms are usually enough. Don't translate the English list one for one: drop terms nobody searches here, add the local high-volume ones, and include the forms people really type, common English loanwords (such as "budget"), romanizations and accepted abbreviations included.

**The category head noun must be reachable:** "budget", "expense" or "spending" as this market searches it, often the local word *and* the English loanword where both are typed. Bare modifiers match nothing.

**Don't spend the budget on the anti-positioning above.** Business-expense, receipt, tax, invoice or bank-sync terms pull the listing toward tools Wren is not.
<!-- end STORE_KEYWORD_DOMAIN -->

<!-- fragment STORE_UNBUNDLE_EXAMPLE -->
"money manager" wastes a byte on the space and blocks recombination; `money,manager` still forms the phrase
<!-- end STORE_UNBUNDLE_EXAMPLE -->

<!-- fragment STORE_EXAMPLE_LISTS -->
Where the source illustrates a point with examples, such as the everyday spending categories "(food, coffee/tea, nightlife, clothes, etc.)", they are illustrations, not fixed copy: swap in things a local reader actually spends on, replace one that isn't salient here ("nightlife" where it is uncommon) with a comparable everyday, money-costing habit, collapse "coffee/tea" to whichever the culture clearly prefers, and drop to three if only three ring true. Keep them concrete, recurring and everyday, and the sentence natural.
<!-- end STORE_EXAMPLE_LISTS -->

<!-- fragment STORE_BULLETS_NOTE -->
The source keeps iCloud *sync* and on-device *storage* as two separate privacy bullets: render both, and don't collapse them into one or add a third. Emphasis the brief calls for, such as the privacy stance, belongs in the surrounding prose, never in an invented bullet.
<!-- end STORE_BULLETS_NOTE -->

## translate_metadata/AUDIT_PROMPT_TEMPLATE.md

<!-- fragment STORE_AUDIT_APP_LINE -->
**Wren**, a native iOS app for fast, everyday expense and budget tracking.
<!-- end STORE_AUDIT_APP_LINE -->

<!-- fragment STORE_AUDIT_VOICE -->
Calm, tidy, quietly warm and understated: an efficient assistant, not a hype machine. No exclamation marks, no ALL-CAPS, no salesy superlatives. It is still marketing copy, so it must be compelling and benefit-led within that calm register.
<!-- end STORE_AUDIT_VOICE -->

<!-- fragment STORE_AUDIT_POSITIONING -->
The positioning must land: Wren is a lightweight, fast, recurring-expense tracker for everyday spending. It is not a full personal-finance suite, a bank-linked app, or a business or travel expense tool; flag copy that drifts into any of those.
<!-- end STORE_AUDIT_POSITIONING -->

<!-- fragment STORE_AUDIT_BRAND -->
"Wren" stays "Wren": never translated, transliterated, glossed or re-cased, and `name` keeps its "Wren – …" form. "iCloud" stays as-is. Domain words like "budget" and "Carry-Over" are not protected, but where an agreed term is given below they must use it; "biweekly" must read as every two weeks, never twice a week.
<!-- end STORE_AUDIT_BRAND -->

<!-- fragment STORE_AUDIT_GLOSSARY -->
Flag (`category: terminology`, severity `medium`) any field that renders one of these terms with a different word or synonym, or swaps between the local word and the English loanword. Required plural, case, article or compound forms of the agreed word are correct. In a longer field, a later shortened mention is fine only where native copy here really would shorten it and the meaning stays clear; a shortened `name` or `subtitle` is a finding. The agreed words for "Budget" and "Expense" must be searchable: their base forms belong in `keywords` unless the name or subtitle already has that exact form (then repeating it is wasted budget, not a requirement). Use the agreed word in your `suggestion`.
<!-- end STORE_AUDIT_GLOSSARY -->

<!-- fragment STORE_AUDIT_RTL_TOKENS -->
("Wren", "iCloud"; the `name` field's mandatory "Wren – …" prefix is exempt)
<!-- end STORE_AUDIT_RTL_TOKENS -->

<!-- fragment STORE_AUDIT_CLAIMS -->
such as bank syncing, transaction import, or multi-currency conversion
<!-- end STORE_AUDIT_CLAIMS -->
