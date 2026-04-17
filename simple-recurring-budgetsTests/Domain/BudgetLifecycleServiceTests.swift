//
//  BudgetLifecycleServiceTests.swift
//  simple-recurring-budgetsTests
//

import Foundation
import SwiftData
import Testing
@testable import simple_recurring_budgets

// MARK: - Shared test helpers (3.1 – 3.3)

/// Fixed-UTC Gregorian calendar for deterministic results in all BudgetLifecycleService tests.
private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

/// Build a `Date` at a given UTC time.
private func d(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
    var comps = DateComponents()
    comps.year = year; comps.month = month; comps.day = day
    comps.hour = hour; comps.minute = 0; comps.second = 0
    comps.timeZone = TimeZone(identifier: "UTC")
    return Calendar(identifier: .gregorian).date(from: comps)!
}

/// Inserts an `ExpenseItem` for the given `budget` in `context`.
@discardableResult
private func expense(amount: Decimal, date: Date, budget: Budget, in context: ModelContext) -> ExpenseItem {
    let item = ExpenseItem(amount: amount, date: date)
    item.budget = budget
    context.insert(item)
    return item
}

/// Builds and configures `AppSettings` with the desired `weekStartDay`.
private func settings(weekStart: Weekday = .sunday) -> AppSettings {
    let s = AppSettings(store: MockKeyValueStore())
    s.weekStartDay = weekStart
    return s
}

// MARK: - No-op path (4.1, 4.2)

struct BudgetLifecycleNoOpTests {

    /// 4.1 — When lastProcessedDate is within the current period and no reset boundary elapsed,
    /// `refreshAndSave` does not mutate any carryOver* field or lastModified.
    @Test func refreshAndSave_noOpWithinPeriod_doesNotMutateFields() throws {
        let container = try TestModelContainer.make()
        let ctx = ModelContext(container)

        let budget = Budget(allocation: 20, period: .daily, resetCadence: .weekly)
        ctx.insert(budget)

        // lastProcessedDate already at today's start (same period as now)
        let now = d(2026, 4, 15, hour: 10)
        budget.carryOverLastProcessedDate = d(2026, 4, 15)         // today's start → no roll
        budget.carryOverLastResetDate = d(2026, 4, 12)             // last Sunday; now is Wed → no reset
        budget.carryOverAmount = Decimal(string: "5.00")!
        let originalLastModified = budget.lastModified

        let s = settings(weekStart: .sunday)
        let result = BudgetLifecycleService.refreshAndSave(budget, settings: s, context: ctx, now: now, calendar: cal)

        #expect(budget.carryOverAmount == Decimal(string: "5.00")!)
        #expect(budget.carryOverLastProcessedDate == d(2026, 4, 15))
        #expect(budget.carryOverLastResetDate == d(2026, 4, 12))
        #expect(budget.lastModified == originalLastModified)

        // 4.2 — result reflects the unmodified carryOverAmount and correct remaining
        #expect(result.carryOverAmount == Decimal(string: "5.00")!)
        #expect(result.remaining == 20) // no expenses
    }

    /// 4.2 — remaining equals allocation − current-period expenses.
    @Test func refreshAndSave_noOp_remainingAccountsForCurrentPeriodExpenses() throws {
        let container = try TestModelContainer.make()
        let ctx = ModelContext(container)

        let budget = Budget(allocation: 20, period: .daily, resetCadence: .weekly)
        ctx.insert(budget)
        try ctx.save()

        let now = d(2026, 4, 15, hour: 10)
        budget.carryOverLastProcessedDate = d(2026, 4, 15) // within today
        budget.carryOverLastResetDate = d(2026, 4, 12)     // no reset
        budget.carryOverAmount = 0

        expense(amount: 7, date: d(2026, 4, 15, hour: 9), budget: budget, in: ctx)

        let result = BudgetLifecycleService.refreshAndSave(budget, settings: settings(), context: ctx, now: now, calendar: cal)

        #expect(result.remaining == 13) // 20 - 7
        #expect(result.carryOverAmount == 0)
    }
}

// MARK: - Roll-only path (5.1, 5.2, 5.3)

struct BudgetLifecycleRollOnlyTests {

    /// 5.1 — Daily budget: yesterday completed; expenses don't equal allocation → roll updates
    /// carryOverAmount, carryOverLastProcessedDate, and bumps lastModified.
    @Test func refreshAndSave_rollOnly_daily_updatesFieldsAndLastModified() throws {
        let container = try TestModelContainer.make()
        let ctx = ModelContext(container)

        let budget = Budget(allocation: 20, period: .daily, resetCadence: .never)
        ctx.insert(budget)

        let now = d(2026, 4, 15, hour: 8)
        budget.carryOverLastProcessedDate = d(2026, 4, 14)  // yesterday's start
        budget.carryOverLastResetDate = d(2026, 4, 15)       // set to now so reset won't fire
        budget.carryOverAmount = 0

        expense(amount: 18, date: d(2026, 4, 14, hour: 10), budget: budget, in: ctx)

        let s = settings(weekStart: .sunday)
        let result = BudgetLifecycleService.refreshAndSave(budget, settings: s, context: ctx, now: now, calendar: cal)

        // roll: 0 + (20 - 18) = 2
        #expect(budget.carryOverAmount == 2)
        #expect(budget.carryOverLastProcessedDate == d(2026, 4, 15))
        #expect(budget.lastModified == now)
        #expect(result.carryOverAmount == 2)
    }

    /// 5.2 — Weekly budget: last week boundary crossed; roll matches BudgetCalculator output.
    @Test func refreshAndSave_rollOnly_weekly_matchesCalculatorOutput() throws {
        let container = try TestModelContainer.make()
        let ctx = ModelContext(container)

        // Budget created on a Sunday so anchor = that Sunday.
        let createdAt = d(2026, 4, 5) // Sunday
        let budget = Budget(allocation: 100, period: .weekly, resetCadence: .never)
        budget.createdAt = createdAt
        ctx.insert(budget)

        let now = d(2026, 4, 12, hour: 1) // just after Sun Apr 12 (new week boundary)
        budget.carryOverLastProcessedDate = d(2026, 4, 5)  // last Sunday
        budget.carryOverLastResetDate = d(2026, 4, 12)      // set forward so reset won't fire
        budget.carryOverAmount = 0

        // Expenses in the Apr 5–11 window: 80 total
        expense(amount: 50, date: d(2026, 4,  6, hour: 10), budget: budget, in: ctx)
        expense(amount: 30, date: d(2026, 4, 10, hour: 10), budget: budget, in: ctx)
        // Out-of-period expense (should be excluded)
        expense(amount: 20, date: d(2026, 4, 13, hour: 10), budget: budget, in: ctx)

        let s = settings(weekStart: .sunday)
        let result = BudgetLifecycleService.refreshAndSave(budget, settings: s, context: ctx, now: now, calendar: cal)

        // 100 - 80 = 20
        #expect(budget.carryOverAmount == 20)
        #expect(budget.carryOverLastProcessedDate == d(2026, 4, 12))
        #expect(result.carryOverAmount == 20)
    }

    /// 5.3 — Multi-period catch-up: 3 completed daily periods.
    @Test func refreshAndSave_rollOnly_multiPeriodCatchUp() throws {
        let container = try TestModelContainer.make()
        let ctx = ModelContext(container)

        let budget = Budget(allocation: 20, period: .daily, resetCadence: .never)
        ctx.insert(budget)

        let now = d(2026, 4, 15, hour: 8)
        budget.carryOverLastProcessedDate = d(2026, 4, 12)  // 3 days ago
        budget.carryOverLastResetDate = d(2026, 4, 15)       // no reset
        budget.carryOverAmount = 0

        // Apr 12: 25 (delta −5), Apr 13: 15 (delta +5), Apr 14: 20 (delta 0) → net 0
        expense(amount: 25, date: d(2026, 4, 12, hour: 10), budget: budget, in: ctx)
        expense(amount: 15, date: d(2026, 4, 13, hour: 10), budget: budget, in: ctx)
        expense(amount: 20, date: d(2026, 4, 14, hour: 10), budget: budget, in: ctx)

        let result = BudgetLifecycleService.refreshAndSave(budget, settings: settings(), context: ctx, now: now, calendar: cal)

        #expect(budget.carryOverAmount == 0)
        #expect(budget.carryOverLastProcessedDate == d(2026, 4, 15))
        #expect(budget.lastModified == now)
        #expect(result.carryOverAmount == 0)
    }
}

// MARK: - Reset-only path (6.1, 6.2, 6.3)

struct BudgetLifecycleResetOnlyTests {

    /// 6.1 — Daily budget, weekly reset cadence: reset boundary crossed → carryOverAmount zeroed,
    /// carryOverLastResetDate advanced; carryOverLastProcessedDate unchanged.
    @Test func refreshAndSave_resetOnly_daily_weekly_zeroesAmountAndAdvancesResetDate() throws {
        let container = try TestModelContainer.make()
        let ctx = ModelContext(container)

        let budget = Budget(allocation: 20, period: .daily, resetCadence: .weekly)
        ctx.insert(budget)

        let now = d(2026, 4, 12) // Sunday — new weekly reset boundary
        // Place processedDate at today's start so no roll fires
        budget.carryOverLastProcessedDate = d(2026, 4, 12)
        budget.carryOverLastResetDate = d(2026, 4, 5)       // last Sunday
        budget.carryOverAmount = Decimal(string: "15.00")!

        let result = BudgetLifecycleService.refreshAndSave(budget, settings: settings(weekStart: .sunday), context: ctx, now: now, calendar: cal)

        #expect(budget.carryOverAmount == 0)
        #expect(budget.carryOverLastResetDate == d(2026, 4, 12))
        #expect(budget.carryOverLastProcessedDate == d(2026, 4, 12)) // unchanged by reset
        #expect(budget.lastModified == now)
        #expect(result.carryOverAmount == 0)
    }

    /// 6.2 — `never` cadence: no fields change regardless of elapsed time; no save.
    @Test func refreshAndSave_neverCadence_noMutation() throws {
        let container = try TestModelContainer.make()
        let ctx = ModelContext(container)

        let budget = Budget(allocation: 20, period: .daily, resetCadence: .never)
        ctx.insert(budget)

        let now = d(2026, 12, 31)
        budget.carryOverLastProcessedDate = d(2026, 12, 31)  // no roll
        budget.carryOverLastResetDate = d(2026, 1, 1)         // long ago, but cadence = never
        budget.carryOverAmount = Decimal(string: "42.00")!
        let originalLastModified = budget.lastModified

        BudgetLifecycleService.refreshAndSave(budget, settings: settings(), context: ctx, now: now, calendar: cal)

        #expect(budget.carryOverAmount == Decimal(string: "42.00")!)
        #expect(budget.carryOverLastResetDate == d(2026, 1, 1))
        #expect(budget.lastModified == originalLastModified)
    }

    /// 6.3 — Multiple reset cadences skipped: carryOverLastResetDate advances to most recent boundary.
    @Test func refreshAndSave_longResetGap_advancesToMostRecentBoundary() throws {
        let container = try TestModelContainer.make()
        let ctx = ModelContext(container)

        let budget = Budget(allocation: 20, period: .daily, resetCadence: .weekly)
        ctx.insert(budget)

        // 6 weeks gap: Mar 1 (Sun) → Apr 12 (Sun)
        let now = d(2026, 4, 12)
        budget.carryOverLastProcessedDate = d(2026, 4, 12)  // no roll
        budget.carryOverLastResetDate = d(2026, 3, 1)        // several weekly cadences ago
        budget.carryOverAmount = Decimal(string: "10.00")!

        BudgetLifecycleService.refreshAndSave(budget, settings: settings(weekStart: .sunday), context: ctx, now: now, calendar: cal)

        #expect(budget.carryOverLastResetDate == d(2026, 4, 12)) // most recent Sunday boundary
        #expect(budget.carryOverAmount == 0)
    }
}

// MARK: - Roll-then-reset ordering (7.1, 7.2)

struct BudgetLifecycleRollThenResetTests {

    /// 7.1 — When both roll and reset fire in the same call, the final state reflects:
    /// roll applied first (carryOverLastProcessedDate advanced), then reset (carryOverAmount = 0).
    @Test func refreshAndSave_rollThenReset_finalStateReflectsBothOperations() throws {
        let container = try TestModelContainer.make()
        let ctx = ModelContext(container)

        // Daily budget, weekly reset cadence (Sunday).
        // now = Sun Apr 12 01:00; lastProcessedDate = Mon Apr 6 (6 days back); lastResetDate = Sun Apr 5.
        let budget = Budget(allocation: 20, period: .daily, resetCadence: .weekly)
        ctx.insert(budget)

        let now = d(2026, 4, 12, hour: 1)
        budget.carryOverLastProcessedDate = d(2026, 4, 6)
        budget.carryOverLastResetDate = d(2026, 4, 5)
        budget.carryOverAmount = 0

        // 6 days: Apr 6–11. Expenses: 20+20+20+20+10+10 = 100; allocation = 6×20 = 120.
        // Roll yields: 0 + (120 − 100) = 20, then reset fires → 0.
        expense(amount: 20, date: d(2026, 4,  6, hour: 10), budget: budget, in: ctx)
        expense(amount: 20, date: d(2026, 4,  7, hour: 10), budget: budget, in: ctx)
        expense(amount: 20, date: d(2026, 4,  8, hour: 10), budget: budget, in: ctx)
        expense(amount: 20, date: d(2026, 4,  9, hour: 10), budget: budget, in: ctx)
        expense(amount: 10, date: d(2026, 4, 10, hour: 10), budget: budget, in: ctx)
        expense(amount: 10, date: d(2026, 4, 11, hour: 10), budget: budget, in: ctx)

        let result = BudgetLifecycleService.refreshAndSave(
            budget, settings: settings(weekStart: .sunday), context: ctx, now: now, calendar: cal
        )

        // Roll happened: processedDate advanced
        #expect(budget.carryOverLastProcessedDate == d(2026, 4, 12))
        // Reset happened: amount zeroed
        #expect(budget.carryOverAmount == 0)
        #expect(budget.carryOverLastResetDate == d(2026, 4, 12))
        // 7.2 — single save proxy: lastModified == now
        #expect(budget.lastModified == now)
        #expect(result.carryOverAmount == 0)
    }
}

// MARK: - Save and lastModified semantics (8.1, 8.2, 8.3)

struct BudgetLifecycleLastModifiedTests {

    /// 8.1 — No change → lastModified is not bumped.
    @Test func refreshAndSave_noChange_lastModifiedUnchanged() throws {
        let container = try TestModelContainer.make()
        let ctx = ModelContext(container)

        let budget = Budget(allocation: 20, period: .daily, resetCadence: .never)
        ctx.insert(budget)

        let now = d(2026, 4, 15, hour: 10)
        budget.carryOverLastProcessedDate = d(2026, 4, 15)
        budget.carryOverLastResetDate = d(2026, 4, 15)
        let originalLastModified = budget.lastModified

        BudgetLifecycleService.refreshAndSave(budget, settings: settings(), context: ctx, now: now, calendar: cal)

        #expect(budget.lastModified == originalLastModified)
    }

    /// 8.2 — Any change → lastModified == now.
    @Test func refreshAndSave_anyChange_lastModifiedBumpedToNow() throws {
        let container = try TestModelContainer.make()
        let ctx = ModelContext(container)

        let budget = Budget(allocation: 20, period: .daily, resetCadence: .never)
        ctx.insert(budget)

        let now = d(2026, 4, 15, hour: 8)
        budget.carryOverLastProcessedDate = d(2026, 4, 14)  // yesterday → roll fires
        budget.carryOverLastResetDate = d(2026, 4, 15)

        BudgetLifecycleService.refreshAndSave(budget, settings: settings(), context: ctx, now: now, calendar: cal)

        #expect(budget.lastModified == now)
    }

    /// 8.3 — remaining is independent of carryOverAmount (PRD §6.7).
    @Test func refreshAndSave_remainingIsIndependentOfCarryOver() throws {
        let container = try TestModelContainer.make()
        let ctx = ModelContext(container)

        let budget = Budget(allocation: 20, period: .daily, resetCadence: .never)
        ctx.insert(budget)

        let now = d(2026, 4, 15, hour: 10)
        budget.carryOverLastProcessedDate = d(2026, 4, 15)  // no roll
        budget.carryOverLastResetDate = d(2026, 4, 15)
        budget.carryOverAmount = Decimal(string: "1000.00")! // large carry-over

        expense(amount: 5, date: d(2026, 4, 15, hour: 9), budget: budget, in: ctx)

        let result = BudgetLifecycleService.refreshAndSave(budget, settings: settings(), context: ctx, now: now, calendar: cal)

        // remaining = 20 − 5 = 15, regardless of carryOverAmount = 1000
        #expect(result.remaining == 15)
    }
}

// MARK: - Biweekly anchor (9.1)

struct BudgetLifecycleBiweeklyAnchorTests {

    /// 9.1 — Budget created mid-week; service derives anchor as the most recent weekStart
    /// day at or before createdAt — matching the budget-math spec's biweekly anchor scenario.
    @Test func refreshAndSave_biweeklyAnchorDerivedFromCreatedAt() throws {
        let container = try TestModelContainer.make()
        let ctx = ModelContext(container)

        // budget-math spec scenario: createdAt = Wed Apr 1, weekStart = Sunday.
        // Expected anchor = Sun Mar 29. Biweekly boundary after anchor+14d = Sun Apr 12.
        let budget = Budget(allocation: 50, period: .biweekly, resetCadence: .never)
        budget.createdAt = d(2026, 4, 1)  // Wednesday
        ctx.insert(budget)

        // Now is Thu Apr 17 — within the Apr 12–25 biweekly window (anchor Mar 29, +14d=Apr 12, +14d=Apr 26).
        let now = d(2026, 4, 17)
        budget.carryOverLastProcessedDate = d(2026, 4, 17)  // no roll
        budget.carryOverLastResetDate = d(2026, 4, 17)

        let s = settings(weekStart: .sunday)
        let result = BudgetLifecycleService.refreshAndSave(budget, settings: s, context: ctx, now: now, calendar: cal)

        // Period start should be Sun Apr 12 (anchor Mar 29 + 14 days = Apr 12)
        #expect(result.periodStart == d(2026, 4, 12))
        // Period end should be Sun Apr 26
        #expect(result.periodEnd == d(2026, 4, 26))
    }
}
