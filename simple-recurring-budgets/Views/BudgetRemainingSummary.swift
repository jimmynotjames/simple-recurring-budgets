import SwiftUI

// MARK: - BudgetRemainingSummary

/// Shared summary block used by `BudgetRowView` (Budgets list) and
/// `BudgetDetailView` header. Renders the displayed-amount + period label
/// (`ViewThatFits` switches H→V at large Dynamic Type) above a `RemainingBar`.
///
/// Presentational only — owns no lifecycle state. Callers pass in the values
/// they've already derived from `BudgetLifecycleResult` and a
/// `BudgetInactiveReason?` for the unified inactive presentation.
///
/// **Displayed amount** depends on the inactive reason:
/// - `.preStart`, `.postEnd` → `allocation` (the budget's current allocation)
/// - `.paused`, `nil` → `remaining` (the calculator's in-period figure)
///
/// The view is `.accessibilityHidden(true)`; callers wrap it and apply their
/// own `.accessibilityLabel` (use `BudgetRemainingSummary.accessibilityLabel(...)`)
/// because the two surfaces differ on whether the budget name is prefixed and
/// whether the surrounding element is a button or a header.
///
/// The chip row (`StatusChipRow`) is intentionally **not** part of this view —
/// the row needs the chips outside its tap target so VoiceOver treats them as
/// separate static-text elements; the detail header follows the same pattern
/// for consistency.
struct BudgetRemainingSummary: View {
  let remaining: Decimal
  let allocation: Decimal
  let periodDisplayLabel: String
  let currencyCode: String
  let currencyDisplay: CurrencyDisplayPreference
  /// When non-nil, applies the unified inactive presentation: dimmed amount
  /// label and a full-width `.secondary` `RemainingBar`. For `.preStart` /
  /// `.postEnd`, the displayed amount switches from `remaining` to `allocation`.
  let inactiveReason: BudgetInactiveReason?

  @ScaledMetric(relativeTo: .headline) private var rowSpacing: CGFloat = 10
  @ScaledMetric(relativeTo: .callout) private var amountSpacing: CGFloat = 6

  /// The amount shown by the large label. For `.preStart` / `.postEnd` this is
  /// the budget's allocation (a meaningful summary when "remaining" has no
  /// in-period interpretation); for `.paused` and `.active` it is the
  /// calculator's `remaining`.
  private var displayedAmount: Decimal {
    switch inactiveReason {
    case .preStart, .postEnd: allocation
    case .paused, .none: remaining
    }
  }

  /// Inactive presentation flag — drives dimming on the amount label and the bar.
  private var isInactive: Bool {
    inactiveReason != nil
  }

  private var isOverBudget: Bool {
    displayedAmount < 0
  }

  /// Fraction of the allocation still available: 1.0 = full allocation remaining,
  /// 0.0 = nothing left. Clamped to [0, 1]; over-budget collapses to 0 and is
  /// signalled separately via `isOverBudget` on `RemainingBar`.
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
      // fixedSize(vertical: true) prevents the parent container from giving the
      // text less height than its natural line height, which causes vertical
      // clipping detected by the accessibility textClipped audit.
      .fixedSize(horizontal: false, vertical: true)
  }

  private var periodText: some View {
    Text(periodDisplayLabel)
      .font(.callout)
      .foregroundStyle(.primary.opacity(0.55)) // 0.55 calibrated for WCAG AA 4.5:1 on white/dark bg
  }
}

// MARK: - Accessibility label

extension BudgetRemainingSummary {
  /// Builds the localized VoiceOver label for a budget summary.
  ///
  /// When `budgetName` is non-nil, it is prepended to the localized body as
  /// `"<name>, <body>"`. We prepend in Swift (rather than weaving the name
  /// into every locale's full sentence) because VoiceOver labels are
  /// comma-separated announcements, not flowing prose — leading-name cadence
  /// is acceptable across all locales and saves us the combinatorial blow-up
  /// of a parallel `withName` key family.
  ///
  /// Pass `budgetName: nil` when the surrounding context already announces
  /// the name (e.g. the detail screen's nav title).
  ///
  /// For `.preStart` / `.postEnd`, the helper dispatches to dedicated keys that
  /// announce the displayed-allocation amount plus the lifecycle date. For
  /// `.paused` and `.active`, the existing on-budget / over-budget keys are
  /// reused — paused-state announcements are not introduced by this helper
  /// (the chip carries the paused-since announcement separately).
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
      // Fall through to the existing recurring / specificDates × on-budget / over-budget label family.
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
