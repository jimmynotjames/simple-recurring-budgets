# Glossary curation — pick the canonical term set for Wren

You are a senior localization architect for **Wren**, a native iOS budgeting app. Before the
app's UI strings are translated into 38 languages, we want a **glossary**: a focused set of
recurring terms that must translate **consistently** everywhere they appear, so two buttons
that both say "Add Expense" never drift apart, and so a compound like "Add Expense" can reuse
the agreed translations of "Add" and "Expense".

Your job: from the candidate data and the full string inventory below, **curate the term set** —
choose the terms worth pinning, and for each write a short context note and part of speech.
**Do not translate anything** — that happens in a later step.

## What makes a good glossary term

Include a term when **consistency across the app matters** for it:
- **Exact repeated strings** — any English string used under more than one key (e.g. "Cancel",
  "Save", "Add Funds", "Current Period", "Delete Expense", "Past Periods"). These must be identical
  wherever they appear. Include essentially all of these.
- **Core domain nouns** — the app's vocabulary: "Budget", "Expense", "Period", "Carry-Over",
  "Funds", "Balance", "Allocation", etc. These should read the same in every screen.
- **High-frequency action verbs** that pair with those nouns — "Add", "Edit", "Delete", "Reset",
  "Resume", "Save" — so compounds ("Add Expense", "Edit Budget", "Delete Budget") compose from a
  stable base.
- **Recurring modifier/field words** — "Start date", "End date", "Today", "When", "Settings".

**Exclude**: full sentences, accessibility hints, one-off phrasings, and generic connective words
that don't carry app meaning. Aim for a **focused set (~40–70 terms)**, not every token. Quality and
reusability over coverage. Prefer the shortest meaningful term: pin "Add" and "Expense" as well as
the phrase "Add Expense" only if the phrase itself recurs and benefits from a single canonical form.

## Protected nouns (include them, mark them clearly)

These are **never translated** — include them as terms so downstream steps lock them, with context
noting they stay verbatim: see `protected` in the candidates JSON (e.g. **Wren**, **iCloud**).
(Domain nouns such as **Carry-Over** are ordinary glossary terms — translate them per locale; they
are not protected.)

## Inputs

### Candidate signals (duplicate strings + frequent words)
```json
{CANDIDATES_JSON}
```

### Full string inventory (key → English → comment) for context
```json
{STRING_INVENTORY_JSON}
```

## Output

Write a **single JSON object** (no markdown fences, no prose) to `{TERMS_OUT_PATH}`:

```json
{
  "terms": [
    {
      "en": "Add Funds",
      "context": "Title/button for the 'add funds' mode of the add-expense screen — putting money into a budget, the opposite of logging a spend.",
      "partOfSpeech": "verb phrase",
      "sourceKeys": ["addEditExpense.title.add.addFunds", "addEditExpense.addFunds.toggle.label"]
    },
    {
      "en": "Add",
      "context": "Imperative action verb used in button/title compounds: Add Expense, Add Budget, Add Funds. Should compose cleanly with nouns.",
      "partOfSpeech": "verb",
      "sourceKeys": ["..."]
    }
  ]
}
```

- `context` must be specific enough that a translator picks the right sense (e.g. "Cancel" = dismiss
  a sheet, not cancel a subscription). Pull meaning from the `comment` fields and surrounding keys.
- `sourceKeys` should list the keys where the term appears (copy from the candidate data; for a
  sub-word term like "Add", list a few representative keys).
- Output **only** the JSON object, written to the path above.
