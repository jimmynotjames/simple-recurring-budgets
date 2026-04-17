//
//  BudgetLifecycleService.swift
//  simple-recurring-budgets
//

import Foundation
import SwiftData

// MARK: - Result Type

/// The display-ready output of a `BudgetLifecycleService.refreshAndSave` call.
///
/// All values reflect post-refresh state: carry-over has been rolled and reset if applicable,
/// `remaining` is independent of carry-over per PRD §6.7.
struct BudgetLifecycleResult {
    /// `allocation − sum(expenses in current period)`. May be negative (overspending).
    /// Not adjusted by carry-over (PRD §6.7).
    let remaining: Decimal
    /// The carry-over amount after rolling and any scheduled reset. Matches `Budget.carryOverAmount`.
    let carryOverAmount: Decimal
    /// Inclusive start of the current budget period.
    let periodStart: Date
    /// Exclusive end of the current budget period (start of the next period).
    let periodEnd: Date
}

// MARK: - BudgetLifecycleService

/// Orchestrates the PRD §6.7 / tech-design §5.4 eager sequence on a `Budget`:
/// roll carry-over → persist → check scheduled reset → persist → compute remaining.
///
/// This is the sole write-back path from `BudgetCalculator` results to SwiftData.
/// ViewModels call `refreshAndSave` eagerly on budget access and consume the returned
/// `BudgetLifecycleResult` for display; they do not call `BudgetCalculator` directly
/// for the roll+reset flow.
enum BudgetLifecycleService {

    // MARK: - Entry Point

    /// Runs the full lifecycle sequence for `budget`, persists any changes via `context`, and returns a display-ready result.
    ///
    /// - Parameters:
    ///   - budget: The budget to refresh.
    ///   - settings: App-wide settings supplying `weekStartDay`.
    ///   - context: The `ModelContext` used to persist any changes.
    ///   - now: The current date. Defaults to `Date()`.
    ///   - calendar: The calendar for all date arithmetic. Defaults to `.autoupdatingCurrent`.
    /// - Returns: A `BudgetLifecycleResult` with values ready for display.
    @discardableResult
    static func refreshAndSave(
        _ budget: Budget,
        settings: AppSettings,
        context: ModelContext,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> BudgetLifecycleResult {
        // Parse stored raw strings — both enums have stable string raw values; failure is
        // unexpected in practice (would indicate corrupted data).
        guard
            let period = BudgetPeriod(rawValue: budget.period),
            let resetCadence = ResetCadence(rawValue: budget.resetCadence)
        else {
            // Fallback: compute display values without mutating the budget.
            let anchor = biweeklyAnchor(createdAt: budget.createdAt, weekStart: settings.weekStartDay, calendar: calendar)
            let pStart = PeriodCalculator.periodStart(containing: now, period: .daily, weekStart: settings.weekStartDay, biweeklyAnchor: anchor, calendar: calendar)
            let pEnd   = PeriodCalculator.periodEnd(containing: now, period: .daily, weekStart: settings.weekStartDay, biweeklyAnchor: anchor, calendar: calendar)
            return BudgetLifecycleResult(
                remaining: BudgetCalculator.remaining(allocation: budget.allocation, expenses: budget.expenseItems, periodStart: pStart, periodEnd: pEnd),
                carryOverAmount: budget.carryOverAmount,
                periodStart: pStart,
                periodEnd: pEnd
            )
        }

        let weekStart = settings.weekStartDay
        let anchor = biweeklyAnchor(createdAt: budget.createdAt, weekStart: weekStart, calendar: calendar)
        var didChange = false

        // ── Step 1: Roll carry-over across completed periods ─────────────────────────────────
        let rollResult = BudgetCalculator.rollCarryOver(
            currentAmount: budget.carryOverAmount,
            allocation: budget.allocation,
            expenses: budget.expenseItems,
            lastProcessedDate: budget.carryOverLastProcessedDate,
            now: now,
            period: period,
            weekStart: weekStart,
            biweeklyAnchor: anchor,
            calendar: calendar
        )

        if rollResult.amount != budget.carryOverAmount || rollResult.lastProcessedDate != budget.carryOverLastProcessedDate {
            budget.carryOverAmount = rollResult.amount
            budget.carryOverLastProcessedDate = rollResult.lastProcessedDate
            didChange = true
        }

        // ── Step 2: Check for scheduled reset ────────────────────────────────────────────────
        let resetResult = BudgetCalculator.checkScheduledReset(
            lastResetDate: budget.carryOverLastResetDate,
            resetCadence: resetCadence,
            now: now,
            period: period,
            weekStart: weekStart,
            biweeklyAnchor: anchor,
            calendar: calendar
        )

        if resetResult.shouldReset, let newResetDate = resetResult.newResetDate {
            budget.carryOverAmount = 0
            budget.carryOverLastResetDate = newResetDate
            didChange = true
        }

        // ── Step 3: Persist once if anything changed ─────────────────────────────────────────
        if didChange {
            budget.lastModified = now
            try? context.save()
        }

        // ── Step 4: Compute display values ───────────────────────────────────────────────────
        let periodStart = PeriodCalculator.periodStart(
            containing: now,
            period: period,
            weekStart: weekStart,
            biweeklyAnchor: anchor,
            calendar: calendar
        )
        let periodEnd = PeriodCalculator.periodEnd(
            containing: now,
            period: period,
            weekStart: weekStart,
            biweeklyAnchor: anchor,
            calendar: calendar
        )
        let remaining = BudgetCalculator.remaining(
            allocation: budget.allocation,
            expenses: budget.expenseItems,
            periodStart: periodStart,
            periodEnd: periodEnd
        )

        return BudgetLifecycleResult(
            remaining: remaining,
            carryOverAmount: budget.carryOverAmount,
            periodStart: periodStart,
            periodEnd: periodEnd
        )
    }

    // MARK: - Private Helpers

    /// Derives the biweekly period anchor as the most recent occurrence of `weekStart`
    /// at or before `createdAt`. Reuses `PeriodCalculator.periodStart` with `.weekly`.
    private static func biweeklyAnchor(createdAt: Date, weekStart: Weekday, calendar: Calendar) -> Date {
        PeriodCalculator.periodStart(
            containing: createdAt,
            period: .weekly,
            weekStart: weekStart,
            biweeklyAnchor: createdAt, // ignored for .weekly
            calendar: calendar
        )
    }
}
