import Foundation

extension Budget {
  /// The period label for list rows and screen headers. For `.specificDates`, the formatted date range
  /// (e.g. "May 18 – Jun 3") via `Date.IntervalFormatStyle` (locale and RTL aware); otherwise
  /// `BudgetPeriod.listLabel`.
  ///
  /// **Same-day window** (`startDate == endDate`, reachable via the snap-forward collapse on
  /// `AddEditBudgetViewModel.startDate`): renders the single date, since `IntervalFormatStyle` is undefined
  /// for an empty `Range<Date>`. It is a valid 1-day window under the inclusive `Budget.endDate` convention.
  ///
  /// **Inverted window** (`endDate < startDate`, a data-integrity violation, typically a partial CloudKit
  /// sync; see `Budget.isWindowValid`): `Range` construction would trap on every Budgets-list row, so release
  /// degrades to the single start date and debug asserts.
  ///
  /// **Why `..<` and not `...`:** `Date.IntervalFormatStyle.format(_:)` only accepts half-open `Range<Date>`.
  /// Both bounds render as dates, so the output matches a closed range; the syntax doesn't contradict
  /// `endDate` being the inclusive last day.
  @MainActor var periodDisplayLabel: String {
    let p = periodEnum
    if p == .specificDates, let start = startDate, let end = endDate {
      // Defense-in-depth (mirrors `AddEditExpenseViewModel.dateRange`): assert in debug on an inverted window;
      // release degrades to a single date so a corrupt record can't crash the list.
      assert(isWindowValid, "periodDisplayLabel: inverted budget window — endDate < startDate")
      return Self.specificDatesDisplayLabel(start: start, end: end)
    }
    return p.listLabel
  }

  /// Period label for a Specific Dates budget, extracted so previews render the same string as production without duplicating formatter configuration.
  static func specificDatesDisplayLabel(start: Date, end: Date) -> String {
    // `>=` (not `==`) so an inverted window takes the single-date path instead of trapping in the `Range`
    // below. The debug assert lives in `periodDisplayLabel` (the production call site), keeping this helper
    // pure so tests can exercise the degraded render.
    if start >= end {
      return start.formatted(date: .abbreviated, time: .omitted)
    }
    return (start ..< end).formatted(
      Date.IntervalFormatStyle(date: .abbreviated, time: .omitted)
    )
  }

  /// Inline period descriptor for VoiceOver labels (e.g. "remaining this *daily* period", "remaining *in this
  /// window*"): `BudgetPeriod.inlineLabel` for recurring periods, a dedicated localized string for `.specificDates`.
  @MainActor var periodInlineLabel: String {
    let p = periodEnum
    if p == .specificDates {
      return String(
        localized: "period.specificDates.inline.budgetRow",
        defaultValue: "in this window",
        comment: "Inline period descriptor used in VoiceOver labels for Specific Dates budgets in the Budgets list and Budget detail screens (e.g. \"$941.00 remaining in this window\")"
      )
    }
    return p.inlineLabel
  }
}
