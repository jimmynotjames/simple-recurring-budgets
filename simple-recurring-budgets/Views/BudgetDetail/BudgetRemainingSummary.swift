import SwiftUI

// MARK: - BudgetRemainingSummary

/// Summary block shared by `BudgetRowView` (list) and the `BudgetDetailView` header:
/// amount + period label (`ViewThatFits` switches H→V at large Dynamic Type) above a
/// `RemainingBar`. Presentational only; callers pass values derived from
/// `BudgetLifecycleResult` plus an optional `BudgetInactiveReason`.
///
/// Displayed amount: `.preStart` / `.postEnd` → `allocation`; `.paused` / `nil` → `remaining`.
///
/// `.accessibilityHidden(true)`: callers wrap it with their own label (use
/// `accessibilityLabel(...)`) because the surfaces differ on name prefix and on
/// button vs header.
///
/// `StatusChipRow` is deliberately not part of this view: the list row needs the chips
/// outside its tap target so VoiceOver reads them as separate elements, and the detail
/// header follows suit.
struct BudgetRemainingSummary: View {
  let remaining: Decimal
  let allocation: Decimal
  let periodDisplayLabel: String
  let currencyCode: String
  let currencyDisplay: CurrencyDisplayPreference
  /// When non-nil: dimmed amount and a full-width `.secondary` `RemainingBar`; for
  /// `.preStart` / `.postEnd` the amount switches from `remaining` to `allocation`.
  let inactiveReason: BudgetInactiveReason?

  @ScaledMetric(relativeTo: .headline) private var rowSpacing: CGFloat = 10
  @ScaledMetric(relativeTo: .callout) private var amountSpacing: CGFloat = 6

  /// Allocation for `.preStart` / `.postEnd` (where "remaining" has no in-period
  /// meaning); the calculator's `remaining` for `.paused` and active.
  private var displayedAmount: Decimal {
    switch inactiveReason {
    case .preStart, .postEnd: allocation
    case .paused, .none: remaining
    }
  }

  /// Drives dimming on the amount and the bar.
  private var isInactive: Bool {
    inactiveReason != nil
  }

  private var isOverBudget: Bool {
    displayedAmount < 0
  }

  /// Fraction of the allocation still available, clamped to [0, 1]. Over-budget is 0 and
  /// signalled separately via `RemainingBar.isOverBudget`.
  private var remainingFraction: Double {
    guard allocation > 0 else { return 0 }
    let ratio = remaining / allocation
    return max(0, min(1, (ratio as NSDecimalNumber).doubleValue))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: rowSpacing) {
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .firstTextBaseline, spacing: amountSpacing) {
          amountText
          periodText.lineLimit(1)
        }
        VStack(alignment: .leading, spacing: amountSpacing) {
          amountText
          periodText
        }
      }

      RemainingBar(remainingFraction: remainingFraction, isOverBudget: isOverBudget, dimmed: isInactive)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityHidden(true)
  }

  private var amountText: some View {
    Text(displayedAmount.formatted(currencyCode: currencyCode, display: currencyDisplay))
      .font(.largeTitle)
      .monospacedDigit()
      .foregroundStyle(dimmedStyle(isOverBudget ? Color.moneyDeficit : Color.primary, when: isInactive))
      .lineLimit(1)
      .truncationMode(.tail)
      .minimumScaleFactor(0.8)
      // Keeps the parent from giving the text less than its natural height, which
      // clips vertically and trips the accessibility textClipped audit.
      .fixedSize(horizontal: false, vertical: true)
  }

  private var periodText: some View {
    Text(periodDisplayLabel)
      .font(.subheadline)
      .foregroundStyle(.readableSecondary)
  }
}

// MARK: - Accessibility label

extension BudgetRemainingSummary {
  /// Localized VoiceOver label for a budget summary.
  ///
  /// A non-nil `budgetName` is prepended as `"<name>, <body>"` in Swift rather than woven
  /// into each locale's sentence: VoiceOver labels are comma-separated announcements, so
  /// leading-name cadence works everywhere and avoids a parallel `withName` key family.
  /// Pass `nil` when the context already announces the name (e.g. the detail nav title).
  ///
  /// `.preStart` / `.postEnd` use dedicated keys (allocation + lifecycle date);
  /// `.paused` and active reuse the on/over-budget keys (the chip announces paused-since).
  static func accessibilityLabel(
    budgetName: String?,
    remaining: Decimal,
    allocation: Decimal,
    isSpecificDates: Bool,
    periodInlineLabel: String,
    currencyCode: String,
    currencyDisplay: CurrencyDisplayPreference,
    inactiveReason: BudgetInactiveReason? = nil
  ) -> String {
    let prefix = budgetName.map { "\($0), " } ?? ""

    switch inactiveReason {
    case let .preStart(startDate):
      let amount = allocation.formatted(currencyCode: currencyCode, display: currencyDisplay)
      let formattedDate = startDate.formatted(date: .abbreviated, time: .omitted)
      let body = String(
        localized: "budget.summary.accessibilityLabel.preStart",
        defaultValue: "\(amount) \(periodInlineLabel) starts \(formattedDate)",
        comment: "VoiceOver label body for a budget summary that has not yet started; args: formatted allocation amount, inline period descriptor, abbreviated start date. Callers may prepend the budget name."
      )
      return prefix + body
    case let .postEnd(endDate):
      let amount = allocation.formatted(currencyCode: currencyCode, display: currencyDisplay)
      let formattedDate = endDate.formatted(date: .abbreviated, time: .omitted)
      let body = String(
        localized: "budget.summary.accessibilityLabel.postEnd",
        defaultValue: "\(amount) \(periodInlineLabel) ended \(formattedDate)",
        comment: "VoiceOver label body for a budget summary whose end date has passed; args: formatted allocation amount, inline period descriptor, abbreviated end date. Callers may prepend the budget name."
      )
      return prefix + body
    case .paused, .none:
      // Recurring / specificDates × on-budget / over-budget label family.
      let isOverBudget = remaining < 0
      let amount = (isOverBudget ? -remaining : remaining)
        .formatted(currencyCode: currencyCode, display: currencyDisplay)
      let body = switch (isSpecificDates, isOverBudget) {
      case (true, true):
        String(
          localized: "budget.summary.accessibilityLabel.overBudget.specificDates",
          defaultValue: "\(amount) over budget \(periodInlineLabel)",
          comment: "VoiceOver label body for an over-budget Specific Dates budget summary; args: positive overage amount, inline period descriptor (e.g. \"in this window\"). Callers may prepend the budget name."
        )
      case (true, false):
        String(
          localized: "budget.summary.accessibilityLabel.specificDates",
          defaultValue: "\(amount) remaining \(periodInlineLabel)",
          comment: "VoiceOver label body for a Specific Dates budget summary; args: remaining amount, inline period descriptor (e.g. \"in this window\"). Callers may prepend the budget name."
        )
      case (false, true):
        String(
          localized: "budget.summary.accessibilityLabel.overBudget",
          defaultValue: "\(amount) over budget this \(periodInlineLabel) period",
          comment: "VoiceOver label body for an over-budget recurring budget summary; args: positive overage amount, period name. Callers may prepend the budget name."
        )
      case (false, false):
        String(
          localized: "budget.summary.accessibilityLabel",
          defaultValue: "\(amount) remaining this \(periodInlineLabel) period",
          comment: "VoiceOver label body for a recurring budget summary; args: remaining amount, period name. Callers may prepend the budget name."
        )
      }
      return prefix + body
    }
  }
}

// MARK: - Preview

#if DEBUG
  private struct SummaryPreview: View {
    var remaining: Decimal = 248.50
    var allocation: Decimal = 400
    var periodDisplayLabel: String = BudgetPeriod.monthly.listLabel
    var inactiveReason: BudgetInactiveReason?

    var body: some View {
      BudgetRemainingSummary(
        remaining: remaining,
        allocation: allocation,
        periodDisplayLabel: periodDisplayLabel,
        currencyCode: "USD",
        currencyDisplay: .symbol,
        inactiveReason: inactiveReason
      )
      .padding()
    }
  }

  extension SummaryPreview {
    static var healthy: SummaryPreview {
      .init()
    }

    static var nearlyEmpty: SummaryPreview {
      .init(remaining: 12, allocation: 400)
    }

    static var overBudget: SummaryPreview {
      .init(remaining: -57.25, allocation: 400)
    }

    static var paused: SummaryPreview {
      .init(remaining: 7.50, allocation: 400, inactiveReason: .paused(since: PreviewDates.pausedSince))
    }

    static var pausedOverBudget: SummaryPreview {
      .init(remaining: -57.25, allocation: 400, inactiveReason: .paused(since: PreviewDates.pausedSince))
    }

    static var preStart: SummaryPreview {
      .init(remaining: 0, allocation: 25, periodDisplayLabel: BudgetPeriod.daily.listLabel, inactiveReason: .preStart(startDate: PreviewDates.preStart))
    }

    static var postEnd: SummaryPreview {
      .init(remaining: 42, allocation: 400, inactiveReason: .postEnd(endDate: PreviewDates.postEnd))
    }

    static var longDateRange: SummaryPreview {
      .init(periodDisplayLabel: Budget.specificDatesDisplayLabel(
        start: PreviewDates.specificDatesStart,
        end: PreviewDates.specificDatesEnd
      ))
    }

    static var zeroAllocation: SummaryPreview {
      .init(remaining: 0, allocation: 0, periodDisplayLabel: BudgetPeriod.weekly.listLabel)
    }
  }

  #Preview("Healthy") { SummaryPreview.healthy }
  #Preview("Nearly empty") { SummaryPreview.nearlyEmpty }
  #Preview("Over budget") { SummaryPreview.overBudget }
  #Preview("Paused") { SummaryPreview.paused }
  #Preview("Paused + over budget · Dark") {
    SummaryPreview.pausedOverBudget.preferredColorScheme(.dark)
  }

  #Preview("Pre-start") { SummaryPreview.preStart }
  #Preview("Pre-start · Dark") { SummaryPreview.preStart.preferredColorScheme(.dark) }
  #Preview("Post-end") { SummaryPreview.postEnd }
  #Preview("Post-end · Dark") { SummaryPreview.postEnd.preferredColorScheme(.dark) }
  #Preview("xxxLarge") { SummaryPreview.longDateRange.dynamicTypeSize(.xxxLarge) }
  #Preview("Zero allocation") { SummaryPreview.zeroAllocation }
#endif
