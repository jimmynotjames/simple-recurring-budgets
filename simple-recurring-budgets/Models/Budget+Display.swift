import Foundation

extension Budget {
  /// The period label to show in list rows and screen headers.
  ///
  /// For `.specificDates` budgets, returns the formatted date range (e.g. "May 18 – Jun 3")
  /// using `Date.IntervalFormatStyle` for full locale and RTL support. For all other period
  /// types, falls back to `BudgetPeriod.listLabel`.
  @MainActor var periodDisplayLabel: String {
    let p = periodEnum
    if p == .specificDates, let start = startDate, let end = endDate {
      return (start ..< end).formatted(
        Date.IntervalFormatStyle(date: .abbreviated, time: .omitted)
      )
    }
    return p.listLabel
  }

  /// The inline period descriptor used in VoiceOver labels (e.g. "remaining this *daily* period",
  /// "remaining *in this window*"). For recurring periods returns `BudgetPeriod.inlineLabel`;
  /// for `.specificDates` returns a dedicated localized string so the sentence reads naturally.
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
