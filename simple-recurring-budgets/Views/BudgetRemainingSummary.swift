import SwiftUI

// MARK: - BudgetRemainingSummary

/// Shared summary block used by `BudgetRowView` (Budgets list) and
/// `BudgetDetailView` header. Renders the remaining-amount + period label
/// (`ViewThatFits` switches H→V at large Dynamic Type) above a `RemainingBar`.
///
/// Presentational only — owns no lifecycle state. Callers pass in the values
/// they've already derived from `BudgetLifecycleResult`.
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
  let isPaused: Bool

  @ScaledMetric(relativeTo: .headline) private var rowSpacing: CGFloat = 10
  @ScaledMetric(relativeTo: .callout) private var amountSpacing: CGFloat = 6

  private var isOverBudget: Bool {
    remaining < 0
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

      RemainingBar(remainingFraction: remainingFraction, isOverBudget: isOverBudget, dimmed: isPaused)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityHidden(true)
  }

  private var amountText: some View {
    Text(remaining.formatted(currencyCode: currencyCode, display: currencyDisplay))
      .font(.largeTitle)
      .monospacedDigit()
      .foregroundStyle(dimmedStyle(isOverBudget ? Color.moneyDeficit : Color.primary, when: isPaused))
      .lineLimit(1)
  }

  private var periodText: some View {
    Text(periodDisplayLabel)
      .font(.callout)
      .foregroundStyle(.secondary)
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
  static func accessibilityLabel(
    budgetName: String?,
    remaining: Decimal,
    isSpecificDates: Bool,
    periodInlineLabel: String,
    currencyCode: String,
    currencyDisplay: CurrencyDisplayPreference
  ) -> String {
    let isOverBudget = remaining < 0
    let amount = (isOverBudget ? -remaining : remaining)
      .formatted(currencyCode: currencyCode, display: currencyDisplay)
    let prefix = budgetName.map { "\($0), " } ?? ""

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

// MARK: - Preview

#if DEBUG
  private struct SummaryPreview: View {
    var remaining: Decimal = 248.50
    var allocation: Decimal = 400
    var periodDisplayLabel: String = "this month"
    var isPaused: Bool = false

    var body: some View {
      BudgetRemainingSummary(
        remaining: remaining,
        allocation: allocation,
        periodDisplayLabel: periodDisplayLabel,
        currencyCode: "USD",
        currencyDisplay: .symbol,
        isPaused: isPaused
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
      .init(isPaused: true)
    }

    static var pausedOverBudget: SummaryPreview {
      .init(remaining: -57.25, allocation: 400, isPaused: true)
    }

    static var longDateRange: SummaryPreview {
      .init(periodDisplayLabel: "Jan 1 – Feb 28")
    }

    static var zeroAllocation: SummaryPreview {
      .init(remaining: 0, allocation: 0, periodDisplayLabel: "this week")
    }
  }

  #Preview("Healthy") { SummaryPreview.healthy }
  #Preview("Nearly empty") { SummaryPreview.nearlyEmpty }
  #Preview("Over budget") { SummaryPreview.overBudget }
  #Preview("Paused") { SummaryPreview.paused }
  #Preview("Paused + over budget · Dark") {
    SummaryPreview.pausedOverBudget.preferredColorScheme(.dark)
  }

  #Preview("xxxLarge") {
    SummaryPreview.longDateRange.dynamicTypeSize(.xxxLarge)
  }

  #Preview("Zero allocation") { SummaryPreview.zeroAllocation }
#endif
