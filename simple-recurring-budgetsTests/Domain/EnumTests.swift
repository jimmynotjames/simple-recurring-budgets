//
//  EnumTests.swift
//  simple-recurring-budgetsTests
//
//  Created by Jimmy Ho on 4/11/26.
//

import Foundation
import Testing
@testable import simple_recurring_budgets

// MARK: - BudgetPeriod

struct BudgetPeriodTests {

    // MARK: Comparable ordering

    @Test func ordering_daily_lessThan_weekly() {
        #expect(BudgetPeriod.daily < BudgetPeriod.weekly)
    }

    @Test func ordering_weekly_lessThan_biweekly() {
        #expect(BudgetPeriod.weekly < BudgetPeriod.biweekly)
    }

    @Test func ordering_biweekly_lessThan_monthly() {
        #expect(BudgetPeriod.biweekly < BudgetPeriod.monthly)
    }

    @Test func ordering_full_chain() {
        let sorted = [BudgetPeriod.monthly, .daily, .biweekly, .weekly].sorted()
        #expect(sorted == [.daily, .weekly, .biweekly, .monthly])
    }

    // MARK: Raw value encoding

    @Test func rawValue_daily() {
        #expect(BudgetPeriod.daily.rawValue == "daily")
    }

    @Test func rawValue_weekly() {
        #expect(BudgetPeriod.weekly.rawValue == "weekly")
    }

    @Test func rawValue_biweekly() {
        #expect(BudgetPeriod.biweekly.rawValue == "biweekly")
    }

    @Test func rawValue_monthly() {
        #expect(BudgetPeriod.monthly.rawValue == "monthly")
    }

    // MARK: defaultResetCadence mapping

    @Test func defaultResetCadence_daily_isWeekly() {
        #expect(BudgetPeriod.daily.defaultResetCadence == .weekly)
    }

    @Test func defaultResetCadence_weekly_isMonthly() {
        #expect(BudgetPeriod.weekly.defaultResetCadence == .monthly)
    }

    @Test func defaultResetCadence_biweekly_isQuarterly() {
        #expect(BudgetPeriod.biweekly.defaultResetCadence == .quarterly)
    }

    @Test func defaultResetCadence_monthly_isQuarterly() {
        #expect(BudgetPeriod.monthly.defaultResetCadence == .quarterly)
    }
}

// MARK: - ResetCadence

struct ResetCadenceTests {

    // MARK: Raw values

    @Test func rawValue_weekly() {
        #expect(ResetCadence.weekly.rawValue == "weekly")
    }

    @Test func rawValue_biweekly() {
        #expect(ResetCadence.biweekly.rawValue == "biweekly")
    }

    @Test func rawValue_monthly() {
        #expect(ResetCadence.monthly.rawValue == "monthly")
    }

    @Test func rawValue_quarterly() {
        #expect(ResetCadence.quarterly.rawValue == "quarterly")
    }

    @Test func rawValue_never() {
        #expect(ResetCadence.never.rawValue == "never")
    }

    // MARK: isBroaderThan

    @Test func never_isBroaderThan_daily() {
        #expect(ResetCadence.never.isBroaderThan(.daily))
    }

    @Test func never_isBroaderThan_monthly() {
        #expect(ResetCadence.never.isBroaderThan(.monthly))
    }

    @Test func quarterly_isBroaderThan_monthly() {
        #expect(ResetCadence.quarterly.isBroaderThan(.monthly))
    }

    @Test func quarterly_isBroaderThan_daily() {
        #expect(ResetCadence.quarterly.isBroaderThan(.daily))
    }

    @Test func monthly_isBroaderThan_weekly() {
        #expect(ResetCadence.monthly.isBroaderThan(.weekly))
    }

    @Test func monthly_notBroaderThan_monthly() {
        #expect(!ResetCadence.monthly.isBroaderThan(.monthly))
    }

    @Test func biweekly_isBroaderThan_weekly() {
        #expect(ResetCadence.biweekly.isBroaderThan(.weekly))
    }

    @Test func biweekly_notBroaderThan_biweekly() {
        #expect(!ResetCadence.biweekly.isBroaderThan(.biweekly))
    }

    @Test func weekly_isBroaderThan_daily() {
        #expect(ResetCadence.weekly.isBroaderThan(.daily))
    }

    @Test func weekly_notBroaderThan_weekly() {
        #expect(!ResetCadence.weekly.isBroaderThan(.weekly))
    }

    // MARK: validResetCadences(for:)

    @Test func validCadences_daily() {
        let valid = ResetCadence.validResetCadences(for: .daily)
        #expect(valid == [.weekly, .biweekly, .monthly, .quarterly, .never])
    }

    @Test func validCadences_weekly() {
        let valid = ResetCadence.validResetCadences(for: .weekly)
        #expect(valid == [.biweekly, .monthly, .quarterly, .never])
    }

    @Test func validCadences_biweekly() {
        let valid = ResetCadence.validResetCadences(for: .biweekly)
        #expect(valid == [.monthly, .quarterly, .never])
    }

    @Test func validCadences_monthly() {
        let valid = ResetCadence.validResetCadences(for: .monthly)
        #expect(valid == [.quarterly, .never])
    }
}

// MARK: - Weekday

struct WeekdayTests {

    @Test func rawValues_sundayThroughSaturday() {
        #expect(Weekday.sunday.rawValue == 1)
        #expect(Weekday.monday.rawValue == 2)
        #expect(Weekday.tuesday.rawValue == 3)
        #expect(Weekday.wednesday.rawValue == 4)
        #expect(Weekday.thursday.rawValue == 5)
        #expect(Weekday.friday.rawValue == 6)
        #expect(Weekday.saturday.rawValue == 7)
    }

    @Test func fromCalendarFirstWeekday_matchesCurrentCalendar() {
        let weekday = Weekday.from(calendarFirstWeekday: Calendar.current.firstWeekday)
        #expect(weekday != nil)
        #expect(weekday?.rawValue == Calendar.current.firstWeekday)
    }

    @Test func fromCalendarFirstWeekday_rejectsOutOfRange() {
        #expect(Weekday.from(calendarFirstWeekday: 0) == nil)
        #expect(Weekday.from(calendarFirstWeekday: 8) == nil)
    }

    @Test func allCases_orderAndIdentifiable() {
        #expect(Weekday.allCases == [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday])
        for day in Weekday.allCases {
            #expect(day.id == day.rawValue)
        }
    }
}
