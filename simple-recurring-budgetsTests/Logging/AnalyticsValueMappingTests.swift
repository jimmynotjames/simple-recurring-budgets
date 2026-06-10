@testable import simple_recurring_budgets
import Testing

/// Locks down the domain-enum → analytics-string mappings in
/// `Analytics+DomainExtensions.swift`. These strings are part of the analytics
/// contract (`docs/analytics-spec.md` §10) — a silent rename would fork every
/// dashboard segment built on the old value, so each case is pinned here.
@Suite("Analytics domain-extension value mappings")
struct AnalyticsValueMappingTests {
  // MARK: - Weekday.analyticsValue

  @Test func weekday_allCases_mapToSnakeCaseNames() {
    #expect(Weekday.sunday.analyticsValue == "sunday")
    #expect(Weekday.monday.analyticsValue == "monday")
    #expect(Weekday.tuesday.analyticsValue == "tuesday")
    #expect(Weekday.wednesday.analyticsValue == "wednesday")
    #expect(Weekday.thursday.analyticsValue == "thursday")
    #expect(Weekday.friday.analyticsValue == "friday")
    #expect(Weekday.saturday.analyticsValue == "saturday")
  }

  // MARK: - CurrencyDisplayPreference.analyticsValue

  @Test func currencyDisplayPreference_allCases_mapToSnakeCaseNames() {
    #expect(CurrencyDisplayPreference.symbol.analyticsValue == "symbol")
    #expect(CurrencyDisplayPreference.code.analyticsValue == "code")
    #expect(CurrencyDisplayPreference.codeAndSymbol.analyticsValue == "code_and_symbol")
  }

  // MARK: - SyncStatus.RowState.analyticsValue

  @Test func syncStatusRowState_allCases_mapToExpectedNames() {
    #expect(SyncStatus.RowState.checking.analyticsValue == "checking")
    #expect(SyncStatus.RowState.available.analyticsValue == "available")
    #expect(SyncStatus.RowState.unavailable.analyticsValue == "unavailable")
    #expect(SyncStatus.RowState.paused.analyticsValue == "paused")
  }
}
