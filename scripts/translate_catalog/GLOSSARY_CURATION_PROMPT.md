{CURATION_INTRO}

Your job: from the candidate data and the full string inventory below, **curate the term set** —
choose the terms worth pinning, and for each write a short context note and part of speech.
**Do not translate anything** — that happens in a later step.

## What makes a good glossary term

Include a term when **consistency across the app matters** for it:
{CURATION_INCLUDE}

{CURATION_EXCLUDE}

## Protected nouns (include them, mark them clearly)

{CURATION_PROTECTED}

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
{CURATION_OUTPUT_EXAMPLE}
  ]
}
```

- `context` must be specific enough that a translator picks the right sense {CURATION_CONTEXT_EXAMPLE}. Pull meaning from
  the `comment` fields and surrounding keys.
- For **ambiguous terms**, spell out the exact meaning and call out false-cognate traps, so the
  disambiguation survives into translation. Choose the unambiguous local term for each.
- `sourceKeys` should list the keys where the term appears (copy from the candidate data; for a
  sub-word term like "Add", list a few representative keys).
- Output **only** the JSON object, written to the path above.
