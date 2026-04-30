# UX Design Brief

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
- **Signature Element:** **Fast expense logging.** From the main budgets screen, there should be only one tap to open a form to add an Expense Item to a Budget. Logging should feel efficient and fast, not filling out a form.

## Key Screens

- **Budgets (root):** Grouped list of Recurring Budgets; each row shows name, remaining this period, and an optional carry-over chip. Glanceable, no dashboard sprawl.
- **Budget detail:** One budget's expense history with current-period state pinned at top; primary **Add Expense** action always within thumb reach.
- **Add/Edit Expense (sheet for add, push for edit):** Amount field focused on open; everything else optional. Designed to dismiss in seconds.
- **Add/Edit Budget (sheet):** Lower-frequency setup — allocation, period, carry-over toggle, ~~reset cadence~~.

> [!NOTE]
> **PAUSED — Reset Cadences feature is not in scope.** Do not include a Reset Cadence control in the Add/Edit Budget sheet (or any UI) while paused. The strikethrough above marks it as inactive; the text is retained for future reference.

- **Settings:** Start of week, currency display, iCloud sync status, support, About. **Skin selection** is future (F-4.01–02). Minimal.

## Navigation

A simple **nav stack** — Budgets → Budget → Expense — with Settings reached via a toolbar item from the root. No bottom tab bar; the app is small enough that extra chrome would feel imposed. Current implementation uses a single `NavigationStack`; a two-column split view on iPad (with Budgets as the sidebar) is a future enhancement.

## iOS Platform Notes

Follow Apple HIG and industry UX best practices where not overridden above. Support Dynamic Type, Dark Mode, VoiceOver, and Reduce Motion as baseline (per PRD §6.4). Use **SF Symbols** throughout; no custom iconography in the default skin. Layouts must adapt cleanly across iPhone, iPad, and macOS targets (per PRD §6.1).