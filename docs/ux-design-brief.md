# UX Design Brief

**Last Updated:** 2026-05-31  
**Author/Owner:** Jimmy Ho

> See `main-prd.md` for product vision, scope, personas, and constraints. This document governs **visual and interaction design only**. The app will eventually support **multiple skins** that may deviate from these guidelines, but these are the default.

## Concept

A recurring-expense tracker that should feel like a first-party Apple app. Aesthetic: **"Tidy and Warm"** — system-default typography and structure, with a small amount of restrained personality so the app reads as cared-for rather than generic.

## Tone & Vibe

The app should feel **calm, tidy, quietly warm**, and **low-key delightful** at times. The voice is a efficient, understated assistant. Default to **Light mode**; it should feel like a freshly organized desk. Avoid exclamation marks, gamification, streak pressure, and celebratory animations over routine logs.

## Core UI Principles

- **Typography:** Default Apple system (SF Pro) or similar. Use **semantic text styles** — Title, Headline, Body, Footnote — never hard-coded point sizes. Dynamic Type is first-class. Currency amounts use **monospaced or rounded digits** so numbers line up and read deliberately.
- **Color:** A restrained, **system-first** palette — dynamic background tones plus one or two muted accents (examples: soft sage, dusty teal, or warm slate, or similar). Surplus and deficit use **semantic colors** that softly indicate positive or negative values. Avoid gradients, saturated colors, and hard black.
- **Layout & Components:** Standard iOS idioms that are aligned with industry best practices —  Content should feel **breathable and scannable**; budgets read like a well-organized accounting ledger, not a dashboard.
- **Progress & Feedback:** Progress is **calm, never scolding**. Indicators like "remaining this period" should be elegant. Carry-over (surplus / deficit) is a small, clearly labeled chip — no streaks, trophies, or alarm reds. Haptics on successful log are soft; nothing loud.
- **Signature Element:** **Fast expense logging.** From the main budgets screen, one tap opens the Add Expense form for a budget. Recents autocomplete on that form (name + amount) further reduces typing for habitual entries. Logging should feel efficient and fast, not like filling out a long form.

## Key Screens

- **Budgets (root):** List of budgets; each row shows optional emoji icon, name, remaining this period, and an optional carry-over chip. Rows in inactive lifecycle states (pre-start, paused, ended) use a dimmed presentation with a single status chip. Glanceable, no dashboard sprawl.
- **Budget detail:** One budget's expense history with current-period state pinned at top; primary **Add Expense** action within thumb reach (swaps to **Resume Budget** when the budget is paused). Toolbar overflow menu hosts lifecycle and destructive actions (edit, pause/resume, reset carry-over, reset budget).
- **Add/Edit Expense (sheet for add, push for edit):** Amount field focused on open; description and date optional. Recents suggestions narrow as the user types. Add Funds toggle for entries that increase remaining. Designed to dismiss in seconds.
- **Add/Edit Budget (sheet):** Lower-frequency setup — allocation, period (including Specific Dates trip-style windows), optional Schedule start/end dates for recurring types, carry-over toggle, optional emoji icon. Reset cadence was permanently removed and does not appear in the UI.

- **Settings:** Start of week, currency display, analytics opt-in, iCloud sync status, support links, About. First-run analytics consent sheet in strict-opt-in locales. **Skin selection** is future (F-4.01–02). Minimal.

## Navigation

A simple **nav stack** — Budgets → Budget → Expense — with Settings reached via a toolbar item from the root. No bottom tab bar; the app is small enough that extra chrome would feel imposed. Current implementation uses a single `NavigationStack`; a two-column split view on iPad (with Budgets as the sidebar) is a future enhancement.

## iOS Platform Notes

Follow Apple HIG and industry UX best practices where not overridden above. Support Dynamic Type, Dark Mode, VoiceOver, and Reduce Motion as baseline (per PRD §6.8). Use **SF Symbols** throughout for app chrome and controls; no custom iconography in the default skin. (Exception: a user may choose an optional **emoji** as a per-Budget icon — that's user content, not app chrome — from the app's curated set; see F-4.03.) Layouts must adapt cleanly across iPhone, iPad, and macOS targets (per PRD §6.1).

---

## Revision history

| Version | Date       | Author   | Changes |
| ------- | ---------- | -------- | ------- |
| 0.2     | 2026-05-31 | Jimmy Ho | Synced with shipped v1 UX: recents, add funds, Specific Dates, pause/resume, inactive row presentation, Settings analytics, reset cadence permanently removed. |
| 0.1     | (prior)    | Jimmy Ho | Initial brief. |
