# Translation pipeline

Translates `Localizable.xcstrings` from English into App Store storefront locales
using AI subagents (Cursor `composer-2-fast`; swap for Haiku in environments where that model is available).

## Scripts

| Script | Purpose |
|---|---|
| `locales.py` | Single source of truth: `LOCALES` list + `LOCALE_NAMES` map |
| `extract.py` | Reads the catalog → writes `tmp/translate-inputs/source.json` |
| `validate.py` | Validates `tmp/translate-outputs/{locale}.json` files against source |
| `merge.py` | Merges validated outputs back into `Localizable.xcstrings` |
| `PROMPT_TEMPLATE.md` | Template used by the parent agent when fanning out per-locale subagents |

## One-time setup

No dependencies beyond Python 3 stdlib.

## Full pipeline (initial backfill or re-generation)

```bash
# 1. Extract source
python3 scripts/translate_catalog/extract.py

# 2. Fan out subagents — one per locale — each reads source.json, writes
#    tmp/translate-outputs/{locale}.json.
#    This step is driven by the parent Cursor agent using the Task tool.
#    See PROMPT_TEMPLATE.md for the prompt each subagent receives.

# 3. Validate all outputs (run after subagents finish)
python3 scripts/translate_catalog/validate.py

# 4. Re-run failed locales (if any), then validate again

# 5. Merge into catalog
python3 scripts/translate_catalog/merge.py

# 6. Build + test
make format && make lint-fix && make build && make test
```

## Adding new strings in the future

When Xcode auto-extracts new keys into `Localizable.xcstrings`:

1. Run `extract.py` — it re-emits `source.json` with only the keys that exist in the catalog (including new ones).
2. Fan out subagents for only the new keys (pass a subset JSON, or re-run all and let `merge.py` overwrite).
3. Validate → merge as above.

## Model note

The pipeline was originally run with Cursor `composer-2-fast`. To regenerate with a different model (e.g. `claude-haiku-*` when available), update the `model` parameter in the Task tool calls and re-run steps 2–5 for any locale you want to improve.
