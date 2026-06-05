# App Store screenshot demo-content — {LOCALE_NAME} ({LOCALE_CODE})

You are creating the **demo data** that the **Wren** budgeting app is seeded with
when its App Store screenshots are captured for the **{LOCALE_NAME}** market. The
screenshots show a few example budgets and recent expenses. Your job: take the
English source structure below and produce a **culturally-tuned, locally
realistic** version for this market.

This is **transcreation, not translation**. The numbers, names, currency, and
even *which* categories appear should look like they belong to a real person in
this market — not a converted copy of the US example.

## Hard structural contract (do NOT change these)

The English source defines the **structure**. For every budget you keep, preserve
exactly:

- `role` — keep verbatim (it ties back to the source; do not invent new roles).
- `period` — keep verbatim (`daily` / `weekly` / `monthly`).
- `startOffsetDays` — keep verbatim (controls how far back the budget started; it
  drives the carry-over chip — changing it breaks the screenshot story).
- `isCarryOverEnabled` — keep verbatim.
- The **number of expenses** in each budget, and each expense's `daysAgo` — keep
  verbatim (these position expenses in the period).

You only change the **content** fields: `name`, `icon`, `currencyCode`,
`allocation`, and each expense's `name` and `amount`.

## What you tune for this market

1. **Budgets (≤ 3).** The source has 3 budgets:
   - `everyday-food` — **mandatory.** Every market has a daily food/eating budget.
   - `groceries` — a weekly groceries/household-food budget. Keep it unless it
     genuinely duplicates the food budget in this market; then you may drop it.
   - `personal` — a personal, **slightly feminine-leaning** discretionary budget
     (the source uses beauty/care). You may keep it, swap it for the
     closest-fitting urban discretionary category for this market (e.g.
     cosmetics, salon, fashion, skincare), or — if no such category fits well —
     **drop it**. Use your own cultural judgment; do not force a category that
     would read as odd, and do not assert facts you are unsure of.
   - **Never exceed 3 budgets.** Fewer is fine. Lean **urban / metropolitan**
     (coffee, tea, cafés, transit, etc. are all fine).

2. **Names.** Short, natural category names a local user would actually type —
   not a literal gloss of the English. Keep budget names short (they appear on a
   list row; aim for ≤ 18 characters in this language so they don't truncate).

3. **Emoji `icon`.** One emoji that fits the category and reads well in this
   market. A single emoji only.

4. **Currency.** Use **`{CURRENCY}`** (this market's currency) for every budget's
   `currencyCode`, unless you have a strong, specific reason to differ (record it
   in `_questions` if so).

5. **Amounts — realistic, NOT converted.** This is the most important rule. Do
   **not** FX-convert the US dollar amounts. Set `allocation` and each expense
   `amount` to what a real person in this market would actually budget/spend.
   - A daily food budget is roughly **one ordinary day of eating** in this market.
   - Keep the food budget's expenses **below** its `allocation` on the days that
     have them, so the budget reads as "on track / a little ahead" (the carry-over
     chip should show a **surplus**, never a deficit).
   - Decimals: write amounts with **{CURRENCY_DECIMALS}** decimal place(s) for
     {CURRENCY} (whole numbers when 0). Amounts are JSON **strings**
     (e.g. "2500" or "12.50"). No currency symbols, no thousands separators.

   Rough daily-food anchors (one person, casual; calibrate, don't copy):
   - US (USD): ~25–35/day · coffee ~4–5 · lunch ~12–16
   - Eurozone (EUR): ~20–30/day · coffee ~3–4 · lunch ~10–14
   - UK (GBP): ~20–28/day · coffee ~3–4 · lunch ~8–12
   - Japan (JPY): ~2000–3000/day · coffee ~400–500 · lunch ~800–1200 (whole yen)
   - South Korea (KRW): ~15000–25000/day · coffee ~4500 · lunch ~9000–12000
   - India (INR): ~300–500/day · chai ~20–40 · meal ~150–300
   - China (CNY): ~50–90/day · coffee ~20–30 · lunch ~25–40
   - Brazil (BRL): ~40–70/day · coffee ~7–10 · lunch ~25–40
   - Mexico (MXN): ~150–300/day · coffee ~50–70 · comida ~80–150
   - Turkey (TRY): scale to current local prices · tea cheap · lunch mid
   - Vietnam (VND): ~150000–300000/day · cà phê ~25000–40000 · meal ~50000–90000
   - Indonesia (IDR): ~80000–160000/day · kopi ~20000–30000 · meal ~30000–60000
   For any market not listed, use your own knowledge of typical 2025–2026 urban
   prices. Sanity-check: the food allocation should be a believable single day.

## Cultural / market note

{CULTURAL_NOTE}

## Output

Write **JSON only** (no markdown fences, no prose) — a single object with a
`budgets` array, each budget in the same shape as the source. Keep the budgets in
the same order as the source (drop from the end if you drop one). Example shape:

```json
{
  "budgets": [
    {
      "role": "everyday-food",
      "name": "...",
      "icon": "🍱",
      "period": "daily",
      "currencyCode": "{CURRENCY}",
      "allocation": "2500",
      "startOffsetDays": 3,
      "isCarryOverEnabled": true,
      "expenses": [
        { "name": "...", "amount": "450", "daysAgo": 0 }
      ]
    }
  ]
}
```

## Decide vs. escalate

Work **autonomously** for all ordinary judgment (names, emoji, amounts, dropping
the personal budget if it doesn't fit). Only add a top-level `_questions` array
when you hit a genuine decision a human would want to weigh in on — e.g. the
market's real currency differs from `{CURRENCY}`, or no discretionary category
fits and you dropped the third budget. Always still write your best-effort
`budgets`; never leave the output empty.

```json
{ "budgets": [ ... ], "_questions": [ { "issue": "...", "decision": "..." } ] }
```

## Source structure (English — transcreate the content, preserve the structure)

{SOURCE_JSON}
