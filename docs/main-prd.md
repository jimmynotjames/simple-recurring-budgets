# Master PRD


| Field              | Value      |
| ------------------ | ---------- |
| **Version**        | 0.1        |
| **Last Updated**   | 2026-04-10 |
| **Author / Owner** | Jimmy Ho   |


> This document is the governing source of truth for the app. It defines the north star, guiding principles, and global constraints that every feature, design decision, and technical choice must align with. For more details about specific features, see [product-features-planning.md](product-features-planning.md).

---

## 1. Vision and North Star

An app that gives users more discipline in their personal spending when it comes to regular, repeating expenses. Examples include daily food expenses or weekly groceries and so on.

---

## 2. Problem Statement

### 2.1 Background / Context

A gazillion apps exist in the Apple App Store to budget and track expenses for personal use, covering a lot of use cases. Examples include expense tracking for business travelers, personal budgeting tools, apps that help a person analyze their finances, tools that connect with banks and credit cards, and on and on. 

### 2.2 Pain Points

Current popular budgeting apps in the marketplace are heavyweight. They make assumptions about the user's mental model of personal finance and try to take over all of a user's personal finances. Onboarding onto these can be a lot. This makes these apps hard to use by most users.

More simple apps may exist to do more simple tracking but they tend to not be visually elegant or are hard to use. 

### 2.3 Target Users

Tech-savvy people who want to control their expenses better. They may or may not have their own personal finance frameworks and apps to handle higher-level budgeting. 

---

## 3. Guiding Principles

1. UX Simplicity - We make no assumptions about the user's mental model of their higher-level finances.
2. Ease of Use - Day to day interactions with the app should feel efficient and easeful.
3. Clarity - Users clearly understand where they stand with respect to their recurring budgets.
4. Delight - The above principles take priority, but when possible, the app should be fun and cute.

---

## 4. Goals and Success Metrics

### 4.1 Business Goals

None

### 4.2 User Goals

None

### 4.3 Key Performance Indicators (KPIs)

- Minimal bugs in production.
- Minimal complaints in App Store reviews.

---

## 5. User Personas

### Persona 1 — Juliette

Juliette, woman, 26 years old, is living a typical, frantic New York life. She has a stable white collar job that easily pays the rent for her shoebox of an apartment but her expenses are a mess. She has no financial tracking system whatsoever. Wrangling her finances is too overwhelming but she thinks she can at least break down the problem into daily and weekly spending. She wants to spend no more than $25/day on food and groceries, $7/day on coffee, and no more than $100/week on beauty supplies and cute clothes. 

### Persona 2 — Colin

Colin, man, 34 years old, is working to support his wife and two kids as a construction foreman in Kansas City. He has a good grasp on his high-level finances, which are on spreadsheets that he and his wife put together. However, day-to-day financial decisions are still a pain point. It's annoying to consult a big spreadsheet on his phone with monthly numbers just to understand if he should splurge on ice cream sundaes for the kids. He can break down his spending allocations into smaller chunks, divided by category and temporal rhythm (daily, weekly), but he doesn't have an easy way to track it. 

### Persona 3 — Paige

Paige, woman, 42, is a project manager living in Fort Collins, CO, with her husband and daughter. She is very organized and knows her finances well. She wants to carve out a budget for herself for those little luxuries and fun expenses, but wants to keep it disciplined. She thinks that setting a daily or weekly spending amount would work, but needs an easy way to track the budget. Current apps are too heavyweight. She enjoys working with tools that are not only useful but fun and cute to use. 

---

## 6. Global Constraints

Constraints that apply universally across every feature and release.

### 6.1 Platform and Compatibility

- iOS, iPadOS, macOS. Primary focus on iOS.
- Only target latest major operating system version and latest general release Swift version.

### 6.2 Performance

- None

### 6.3 Security and Privacy

- Protect user's privacy with the usual Apple tools, such as native encryption of application data files, DBs, etc.

### 6.4 Accessibility

We will support

- Dynamic Type
- VoiceOver

### 6.5 Localization / Internationalization

- Support all global users with access to Apple apps. 
- Support for all global languages
- Includes supporting all currency symbols, but not currency exchange conversions.

### 6.6 Data and Storage

- Persist data with **SwiftData** and sync across the user’s devices with **CloudKit**.

### 6.7 Carry-over behavior

These rules apply to every Budget **for which carry-over is enabled**. When carry-over is turned off for a budget (see product features), the carry-over amount is not computed or displayed for that budget. Rules are **per budget**; there is no aggregation across budgets.

**Display (independent numbers)**

- **Remaining for the current Budget Period** — How much of *this period’s* allocation is left. It is **not** increased or reduced by the separate carry-over figure. Example: with a $20/day allocation, the primary “left to spend” for today shows amounts derived only from today’s $20 and today’s expenses, not mixed into a single combined cap.
- **Carry-over** — A separate, signed cumulative total that reflects how far ahead or behind the user is relative to their recurring allocation, carried across Budget Periods until it is reset. Copy and formatting should read cleanly for both directions (e.g. surplus vs deficit); exact strings are a design choice.

**How carry-over moves**

- At each **Budget Period** boundary (e.g. each new day for a daily budget), fold in the outcome of the period that just ended: add `(allocation for that period − total expenses counted against that period)` to the carry-over amount. Example: carry-over was a $5 deficit; allocation for the day was $20; the user spent $18. The $2 unspent vs that allocation reduces the deficit, so carry-over becomes a $3 deficit before the new period’s expenses apply.
- **Positive and negative** carry-over amounts both carry forward according to that rule until reset.

**Resetting carry-over**

- **Manual** — The Budget screen provides a control to reset carry-over to zero (with confirmation). Per-budget only.
- **Scheduled** — On **Add/Edit Budget screen**, the user chooses how often carry-over resets automatically. **Reset cadence** options are **weekly**, **biweekly**, **monthly**, **quarterly**, or **never** (no automatic reset; the user relies on manual reset only). Which options are available depends on **Budget Period** (each cadence must be broader than the budget’s period; see product features). The **longest** calendar-based cadence is **quarterly**. **Defaults** for new budgets: daily → weekly; weekly → monthly; biweekly → quarterly; monthly → quarterly. **Scheduled** resets fire at **period boundaries** — the first boundary after the cadence interval has elapsed — never mid-period, so biweekly and other non-calendar periods stay aligned with full cycles. Weekly reset boundaries respect the app’s configured start of week where applicable (see product features).
- **Carry-over optional** — A budget may have carry-over turned off (see product features); when off, the carry-over amount is not computed or shown for that budget.
- **Monthly Budgets** — When the Budget Period is **monthly**, the default reset cadence is **quarterly**. Carry-over accumulates across months and resets every quarter. The user may choose a different cadence (quarterly or never) on the Add/Edit Budget screen.

---

## 7. Technical Foundations

*High-level technical decisions that constrain all downstream work. More specifics wil be worked out during feature development.*

The companion technical reference for implementation and tooling is [tech-design-doc.md](tech-design-doc.md) (architecture, SwiftData/CloudKit, and related engineering choices).

### 7.1 Language and Frameworks

- Latest stable Swift version.
- Prefer SwiftUI, unless the capability does not exist. 
- Prefer latest Swift testing infrastructure.

### 7.2 Data Model (High-Level)

High-level entities include:

- Recurring Budget - A spending allowance that repeats. Carries configuration for Budget Period, allocation, **currency (per budget)**, and **carry-over reset cadence** (subject to [§6.7](#67-carry-over-behavior)).
- Expense Item
  - A single expense

### 7.3 Third-Party Dependencies Policy

- Prefer using Apple's libraries and frameworks to external.
- All dependencies should be canonical and industry best-practice.
- All dependencies must be actively maintained.
- All dependencies should pull the latest version.

### 7.4 General Architecture Constraints

- Except for leveraging Apple's CloudKit and similar cloud services that are free to the developer, there will be no backend.

---

## 8. Design Foundations

### 8.1 Visual Design Principles

- Adhere to Apple's Human Interface Guidelines and latest industry best practices. If the two conflict, ask for clarification. 
- Visual design should be minimalistic and elegant. 
- Use default Apple typography, spacings, margins, etc.

### 8.2 Branding

- Vibes: Simple, elegant, and cute.

### 8.3 Information Architecture

Screens:

- Budgets screen — List of Recurring Budgets with current allocations
- Budget screen — List of Expense Items for one Budget
- Add/Edit Budget screen — Create or edit a Budget (entity).
- Add/Edit/View Expense Item screen — Create, edit, or view an Expense Item (entity).
- Settings screen

---

## 9. Open Questions

- None

---

## 10. Appendix

### 10.1 Glossary

- Recurring Budget (AKA Budget) - An allocation of available spending that repeats the allocation at regular time intervals. The supported period values are defined in app code (see `BudgetPeriod` or equivalent).
- Expense Item (AKA Expense or Transaction) - A specific expense.
- Budget Period - The repeating time interval the Budget allocates funds to. The canonical set of cases and their string values are defined in app code (see `BudgetPeriod` or equivalent).
- Carry-over Amount (AKA CarryOver) - A per-budget, signed cumulative total: surplus (under-spent relative to allocation over time) or deficit (over-spent). It is **shown separately** from “remaining for this Budget Period” (which is not adjusted by carry-over for display). Updated at each Budget Period boundary per [§6.7](#67-carry-over-behavior); can be cleared manually or on a user-configured schedule. Which reset cadence options exist, and how “manual only” is represented, are defined in app code (see `ResetCadence` or equivalent).
- Reset cadence - How often carry-over is cleared automatically. Valid cadences and how they relate to Budget Period are defined in app code (see `ResetCadence` and related validation). This glossary does not enumerate values; refer to the code for the latest list.

### 10.2 References

None

### 10.3 Revision History


| Version | Date       | Author   | Changes          |
| ------- | ---------- | -------- | ---------------- |
| 0.1     | 2026-04-10 | Jimmy Ho | Initial template |
|         |            |          |                  |


