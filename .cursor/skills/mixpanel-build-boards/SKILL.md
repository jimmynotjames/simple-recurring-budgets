---
name: mixpanel-build-boards
description: Build, edit, or reconcile Mixpanel dashboards ("boards") in the Wren App - Prod project through the Mixpanel MCP. Use when asked to create or update analytics dashboards/boards, ship the Phase 1 (or Phase 2) board set, swap one report for another, or reconcile boards against docs/analytics-spec.md §11. Drives the Mixpanel MCP (Get-Business-Context → Run-Query → Create-Dashboard / Update-Dashboard), treats docs/analytics-spec.md §11 plus live Mixpanel as the source of truth, and handles the Free-vs-Growth saved-report cap. Does NOT decide what to measure — that is owned by the analytics spec. Invoked via /mixpanel-build-boards.
---

# Build Mixpanel boards

Create, edit, and reconcile Mixpanel **boards** (dashboards) for the Wren app through the
**Mixpanel MCP**. This skill is the *how* — the MCP procedure plus the Wren-specific
coordinates and cap rules. It is deliberately **not** the *what*: which boards exist and
what they measure is owned by `docs/analytics-spec.md` §11 (with §3 product questions, §9
events, §10 properties, §5 PII contract). Do not duplicate that content here — reference it.

**Source of truth, in order:** live Mixpanel state → `docs/analytics-spec.md` → this skill.
On any mismatch, Mixpanel and the spec win; update the spec (and this skill) to match —
never the reverse.

## When to use

"Build the Phase 1 / Phase 2 boards", "add a dashboard for X", "reconcile the boards with
the spec", "swap report Y for Z", "the boards drifted from the doc".

## Projects (Wren)

| Project          | project_id | workspace_id | Role                                                          |
| ---------------- | ---------- | ------------ | ------------------------------------------------------------ |
| Wren App - Prod  | 4036089    | 4532359      | **Canonical.** Fed by App Store + TestFlight. Build here.    |
| Wren App - Dev   | 4036090    | 4532360      | Scratchpad for experiments; not tracked in the spec.         |

Ids are stable but re-confirm with `Get-Projects` (a renamed/recreated project changes them).

## Recipe

1. **Business context first.** Call `Get-Business-Context` (pass `project_id`) as the FIRST
   Mixpanel MCP call — the server requires it. Then `Get-Projects` to confirm the Prod id.
2. **Read the spec.** From `docs/analytics-spec.md`: §11.3 / §11.4 (which boards to build +
   the Free-tier survivors), §11.2 (board-writing conventions), §9 / §10 (canonical event +
   property names), §5 (PII allow/deny). Build against the **canonical names** even when no
   data has arrived yet — empty boards populate as events flow.
3. **Check the live schema.** `Get-Events` and `List-Properties` on Prod to see what exists.
   Missing events/properties are fine: `Run-Query` accepts not-yet-seen events and returns
   empty results (no error), so forward-looking boards are valid.
4. **Learn the query shape.** For anything past a trivial single-metric insight, call
   `Get-Query-Schema` for the report type (`insights` | `funnels` | `retention` | `flows`)
   before assembling the `report` object.
5. **Mint the reports.** For each tile, `Run-Query` with `skip_results: true` to get a
   `query_id` (don't pull results you won't read). One `query_id` per tile. Keep parallel
   batches small (≤4) to avoid 502s.
6. **Assemble the board.** `Create-Dashboard` with rows: a one-line framing **text card**
   (row 1) + `report` cells referencing the `query_id`s (≤4 cells/row, ≤30 rows). To extend
   an existing board, `Update-Dashboard` — add a row with `rows: [["temp-row","add"]]` and a
   cell with `cells: [["temp-cell","create","report",{row_id,query_id,name,description}]]`.
   Get cell/row ids first with `Get-Dashboard(include_layout=true)`.
7. **Verify + reconcile.** `Search-Entities` (dashboards + report types) to confirm board and
   report counts, then update `docs/analytics-spec.md` §11.3 status + revision history.

## Board-writing conventions (spec §11.2)

- Write for a human reader: short, plain names/descriptions about the **user behavior**, with
  one `§3.x` doc ref. No phase numbers, ticket ids, "built via MCP", or filter mechanics in
  names/descriptions.
- One short framing text card per board; don't over-explain.
- Don't force what the MCP can't express — drop a minor aspect rather than build an awkward
  proxy, or leave a one-line self-service note for a human to finish in the Mixpanel UI.
- **Never** put a PII / deny-listed field (§5) into a query: no `ExpenseItem` fields, no
  free-text beyond `budget_name`, no money beyond `budget_allocation_amount`.

## Plan & the saved-report cap (decide before adding reports)

The current plan (Free vs Growth) is recorded in **spec §11.2** — read it there; do not
hardcode it here.

- **Growth plan:** unlimited saved reports ($0/month under the 1M-events/month free
  allotment, then $0.28 per 1K). Build the full set freely.
- **Free plan:** **5 saved reports per project, per user** (every chart tile = one saved
  report; boards and text cards are free). When on Free:
  - Keep only the **5 survivors** listed in spec §11.4; delete every other tile.
  - **Free a slot before adding one:** `Update-Dashboard` with a `["cell-id","delete"]`
    cell frees that report's slot; `Delete-Dashboard` frees all of a board's slots. There is
    **no** standalone delete-report MCP tool.
  - Confirm any swap with the maintainer — survivors were chosen as highest-value.
- Detect the cap empirically: `Create-Dashboard` / `Update-Dashboard` rejects with
  `User has reached their limit of saved reports for this project` when you'd exceed 5.

## MCP tool permissions (what runs unattended vs. prompts)

The Mixpanel MCP tools are allowlisted in `.claude/settings.json` by **blast radius**, so
this skill's read path and routine board authoring run without permission prompts, while
destructive or project-wide writes still stop for confirmation:

- **Allowlisted — run unattended:**
  - *All read-only tools* — every `Get-*`, `List-*`, `Search-*`, `Display-Query`,
    `Find-Duplicate-Event-Groups`, `Explain-*`, and `*-Guidance` helper (covers the entire
    recipe's read path).
  - *Board/metric authoring* (single-entity, reversible): `Create-Dashboard`,
    `Update-Dashboard`, `Duplicate-Dashboard`, `Create-Metric`, `Update-Metric`.
- **Not allowlisted — always prompts (deliberate confirmation points):**
  - *Destructive:* `Delete-Dashboard`, `Delete-Tag`. A delete-based slot swap on the Free cap
    (above) therefore prompts — which is the intended maintainer-confirm gate for dropping a
    survivor tile.
  - *Project-wide taxonomy rewrites:* `Edit-Event`, `Edit-Property`, `Bulk-Edit-Events`,
    `Bulk-Edit-Properties`, `Merge-Event-Group`.
  - *Global / out-of-scope:* `Update-Business-Context`, and all experiment / feature-flag
    writes (not used by this workflow).

When adding new Mixpanel tools to the allowlist, keep this boundary: read-only always;
single-entity board/metric writes yes; deletes, taxonomy rewrites, business-context, and
experiment/flag writes stay prompting.

## Gotchas

- **First MCP call must be `Get-Business-Context`** — the server requires it.
- **Unattached `Run-Query` drafts don't persist** as saved reports — they don't appear in
  `Search-Entities` and don't count against the Free cap. A `query_id` still survives a brief
  outage long enough to attach to a board.
- **Auto-generated "🌱 Starter Board" reports** are owned by the Mixpanel system user, so they
  don't count against the Free quota; delete the Starter Board if it clutters Prod.
- **The Free cap is per project** — deleting reports/boards in Dev or other projects frees
  nothing in Prod.
- **Transient 502s under burst load** — the MCP endpoint throttles; both reads and writes can
  502 during a blip. Keep parallel batches ≤4, back off, and retry (attached reports and
  in-flight `query_id`s survive).
- **`$session_start` / `$session_end` exist** even though the app sets
  `trackAutomaticEvents: false` — Mixpanel sessionizes server-side, so sessions ≈ clusters of
  `app_opened`.

## After building

- Reconcile `docs/analytics-spec.md`: §11.3 (board status), §11.4 (survivor set), and the
  revision-history table to match live Mixpanel.
- If the plan or cap facts changed, update spec §11.2 and the `reference_mixpanel_free_report_cap`
  memory so future sessions branch correctly.
