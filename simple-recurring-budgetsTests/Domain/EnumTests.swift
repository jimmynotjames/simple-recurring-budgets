import Foundation
@testable import simple_recurring_budgets
import Testing

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

  @Test func ordering_monthly_lessThan_specificDates() {
    #expect(BudgetPeriod.monthly < BudgetPeriod.specificDates)
  }

  @Test func ordering_full_chain() {
    let sorted = [BudgetPeriod.monthly, .daily, .specificDates, .biweekly, .weekly].sorted()
    #expect(sorted == [.daily, .weekly, .biweekly, .monthly, .specificDates])
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

  @Test func rawValue_specificDates() {
    #expect(BudgetPeriod.specificDates.rawValue == "specificDates")
  }
}

// MARK: - RecurringBudgetPeriod

struct RecurringBudgetPeriodTests {
  @Test func init_daily_succeeds() {
    #expect(RecurringBudgetPeriod(.daily) != nil)
  }

  @Test func init_weekly_succeeds() {
    #expect(RecurringBudgetPeriod(.weekly) != nil)
  }

  @Test func init_biweekly_succeeds() {
    #expect(RecurringBudgetPeriod(.biweekly) != nil)
  }

  @Test func init_monthly_succeeds() {
    #expect(RecurringBudgetPeriod(.monthly) != nil)
  }

  @Test func init_specificDates_returnsNil() {
    #expect(RecurringBudgetPeriod(.specificDates) == nil)
  }
}

// MARK: - LifecycleEventKind

struct LifecycleEventKindTests {
  @Test func rawValue_pause() {
    #expect(LifecycleEventKind.pause.rawValue == "pause")
  }

  @Test func rawValue_resume() {
    #expect(LifecycleEventKind.resume.rawValue == "resume")
  }

  @Test func allCases_hasTwo() {
    #expect(LifecycleEventKind.allCases.count == 2)
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
