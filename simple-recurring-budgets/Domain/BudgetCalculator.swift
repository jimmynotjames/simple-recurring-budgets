//
//  BudgetCalculator.swift
//  simple-recurring-budgets
//

import Foundation

// MARK: - Result Types

/// The result of a carry-over roll computation.
struct CarryOverRollResult {
    /// The updated carry-over amount after folding all completed periods.
    let amount: Decimal
    /// The start of the last period that was folded in; write back to `carryOverLastProcessedDate`.
    let lastProcessedDate: Date
}

/// The result of a scheduled reset boundary check.
struct ResetCheckResult {
    /// `true` when a reset cadence boundary has been crossed since `lastResetDate`.
    let shouldReset: Bool
    /// The period boundary at which the reset fires; `nil` when `shouldReset` is `false`.
    let newResetDate: Date?
}

// MARK: - BudgetCalculator

/// Financial math service built on `PeriodCalculator`.
///
/// All methods are pure functions with no SwiftData or SwiftUI dependencies.
/// Production callers pass `Calendar.autoupdatingCurrent`; tests inject a fixed-UTC calendar.
///
/// `isCarryOverEnabled` is a display-only flag consumed by the UI layer.
/// The calculator always computes carry-over regardless of that setting so the figure is
/// immediately correct if the user re-enables carry-over after a period of disabling it.
enum BudgetCalculator {

    // MARK: - Remaining for Current Period

    /// Returns `allocation − sum(expenses in [periodStart, periodEnd))`.
    ///
    /// The result may be negative (overspending). This value is independent of carry-over (PRD §6.7).
    /// Add-funds transactions use negative `amount` values (per `ExpenseItem` convention) and
    /// therefore reduce the expense total, increasing `remaining`.
    static func remaining(
        allocation: Decimal,
        expenses: [ExpenseItem],
        periodStart: Date,
        periodEnd: Date
    ) -> Decimal {
        let inPeriod = expenses.filter { $0.date >= periodStart && $0.date < periodEnd }
        let total = inPeriod.reduce(Decimal(0)) { $0 + $1.amount }
        return allocation - total
    }

    // MARK: - Carry-Over Roll

    /// Walks all completed period boundaries since `lastProcessedDate` and folds
    /// `(allocation − sum of period expenses)` into the running carry-over amount.
    ///
    /// Always executes regardless of `isCarryOverEnabled` (display-only flag).
    /// Returns unchanged values when no period boundary has been fully completed since
    /// `lastProcessedDate`.
    ///
    /// - Parameters:
    ///   - currentAmount: The current carry-over amount to accumulate into.
    ///   - allocation: The per-period allocation for this budget.
    ///   - expenses: All expenses for this budget (filtering to each period happens internally).
    ///   - lastProcessedDate: The date through which carry-over has already been computed.
    ///   - now: The current date/time.
    ///   - period: The budget's repeating period.
    ///   - weekStart: The user's configured week-start day.
    ///   - biweeklyAnchor: The cycle anchor for biweekly periods.
    ///   - calendar: The calendar to use for all date arithmetic.
    static func rollCarryOver(
        currentAmount: Decimal,
        allocation: Decimal,
        expenses: [ExpenseItem],
        lastProcessedDate: Date,
        now: Date,
        period: BudgetPeriod,
        weekStart: Weekday,
        biweeklyAnchor: Date,
        calendar: Calendar
    ) -> CarryOverRollResult {
        let boundaries = PeriodCalculator.periodBoundaries(
            from: lastProcessedDate,
            to: now,
            period: period,
            weekStart: weekStart,
            biweeklyAnchor: biweeklyAnchor,
            calendar: calendar
        )

        var amount = currentAmount
        var lastDate = lastProcessedDate

        for (i, boundary) in boundaries.enumerated() {
            let nextBoundary: Date
            if i + 1 < boundaries.count {
                nextBoundary = boundaries[i + 1]
            } else {
                nextBoundary = PeriodCalculator.periodEnd(
                    containing: boundary,
                    period: period,
                    weekStart: weekStart,
                    biweeklyAnchor: biweeklyAnchor,
                    calendar: calendar
                )
            }

            // Only process periods that have fully completed (nextBoundary is in the past or now)
            guard nextBoundary <= now else { break }

            let periodRemaining = Self.remaining(
                allocation: allocation,
                expenses: expenses,
                periodStart: boundary,
                periodEnd: nextBoundary
            )
            amount += periodRemaining
            lastDate = nextBoundary
        }

        return CarryOverRollResult(amount: amount, lastProcessedDate: lastDate)
    }

    // MARK: - Scheduled Reset

    /// Determines whether a scheduled reset boundary has been crossed since `lastResetDate`.
    ///
    /// Reset boundaries align to the budget's period boundaries (never mid-period).
    /// When multiple cadence intervals have elapsed (app not opened for a long time), returns
    /// the most recent applicable boundary at or before `now`.
    ///
    /// Always returns no-reset for `.never` cadence.
    static func checkScheduledReset(
        lastResetDate: Date,
        resetCadence: ResetCadence,
        now: Date,
        period: BudgetPeriod,
        weekStart: Weekday,
        biweeklyAnchor: Date,
        calendar: Calendar
    ) -> ResetCheckResult {
        guard resetCadence != .never else {
            return ResetCheckResult(shouldReset: false, newResetDate: nil)
        }

        let firstCandidate = advanced(from: lastResetDate, by: resetCadence, calendar: calendar)
        let firstBoundary = firstPeriodBoundaryAtOrAfter(
            firstCandidate,
            period: period,
            weekStart: weekStart,
            biweeklyAnchor: biweeklyAnchor,
            calendar: calendar
        )

        guard firstBoundary <= now else {
            return ResetCheckResult(shouldReset: false, newResetDate: nil)
        }

        // Walk forward to find the most recent reset boundary at or before now.
        var latestReset = firstBoundary
        while true {
            let nextCandidate = advanced(from: latestReset, by: resetCadence, calendar: calendar)
            let nextBoundary = firstPeriodBoundaryAtOrAfter(
                nextCandidate,
                period: period,
                weekStart: weekStart,
                biweeklyAnchor: biweeklyAnchor,
                calendar: calendar
            )
            guard nextBoundary <= now else { break }
            latestReset = nextBoundary
        }

        return ResetCheckResult(shouldReset: true, newResetDate: latestReset)
    }

    // MARK: - Private Helpers

    /// Advances `date` by one cadence interval.
    private static func advanced(from date: Date, by cadence: ResetCadence, calendar: Calendar) -> Date {
        switch cadence {
        case .weekly:    return calendar.date(byAdding: .day,   value: 7,  to: date)!
        case .biweekly:  return calendar.date(byAdding: .day,   value: 14, to: date)!
        case .monthly:   return calendar.date(byAdding: .month, value: 1,  to: date)!
        case .quarterly: return calendar.date(byAdding: .month, value: 3,  to: date)!
        case .never:     return date
        }
    }

    /// Returns the first period boundary that is >= `date`.
    private static func firstPeriodBoundaryAtOrAfter(
        _ date: Date,
        period: BudgetPeriod,
        weekStart: Weekday,
        biweeklyAnchor: Date,
        calendar: Calendar
    ) -> Date {
        let start = PeriodCalculator.periodStart(
            containing: date,
            period: period,
            weekStart: weekStart,
            biweeklyAnchor: biweeklyAnchor,
            calendar: calendar
        )
        if start >= date {
            return start
        }
        return PeriodCalculator.periodEnd(
            containing: date,
            period: period,
            weekStart: weekStart,
            biweeklyAnchor: biweeklyAnchor,
            calendar: calendar
        )
    }
}
