import Foundation

extension Budget {
  /// The budget name, prefixed by its `icon` emoji and a single space when one is
  /// set (e.g. "☕ Coffee"), or the bare name otherwise. Single source of truth for
  /// the icon-as-name-prefix rule (F-4.03) used by `BudgetsView` (list rows) and
  /// `BudgetDetailView` (nav title). The icon is decorative; callers that need
  /// VoiceOver to read the name without it announce `name` separately.
  @MainActor var iconPrefixedName: String {
    guard let icon, !icon.isEmpty else { return name }
    return "\(icon) \(name)"
  }

  /// The period label to show in list rows and screen headers.
  ///
  /// For `.specificDates` budgets, returns the formatted date range (e.g. "May 18 – Jun 3")
  /// using `Date.IntervalFormatStyle` for full locale and RTL support. For all other period
  /// types, falls back to `BudgetPeriod.listLabel`.
  ///
  /// **Same-day window** (`startDate == endDate`, possible via the snap-forward collapse
  /// path on `AddEditBudgetViewModel.startDate`): renders the single date alone rather
  /// than passing an empty `Range<Date>` to `IntervalFormatStyle` (undefined for empty
  /// ranges). A same-day Specific Dates budget is a valid 1-day window per the
  /// `Budget.endDate` inclusive-day convention.
  ///
  /// **Why `..<` and not `...`:** `Date.IntervalFormatStyle.format(_:)` only accepts
  /// `Range<Date>` (half-open); there's no closed-range overload. The formatter just
  /// emits both bounds as dates, so the rendered string is identical to what a closed
  /// range would render — the half-open *syntax* does not contradict the semantic
  /// convention that `endDate` is the inclusive last day (see `Budget.endDate`).
  @MainActor var periodDisplayLabel: String {
    let p = periodEnum
    if p == .specificDates, let start = startDate, let end = endDate {
      return Self.specificDatesDisplayLabel(start: start, end: end)
    }
    return p.listLabel
  }

  /// Renders the period label shown for a Specific Dates budget. Extracted so SwiftUI
  /// previews can produce the same string production renders without duplicating the
  /// formatter configuration.
  static func specificDatesDisplayLabel(start: Date, end: Date) -> String {
    if start == end {
      return start.formatted(date: .abbreviated, time: .omitted)
    }
    return (start ..< end).formatted(
      Date.IntervalFormatStyle(date: .abbreviated, time: .omitted)
    )
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
