import SwiftUI

/// Decorative fuel-gauge bar under the remaining amount on budget surfaces.
///
/// Fraction is **0.0–1.0**, already clamped; when over budget, pass `isOverBudget: true`
/// so the bar fills in the deficit color instead of emptying in accent color.
struct RemainingBar: View {
  let remainingFraction: Double
  let isOverBudget: Bool
  /// When `true`, the filled bar renders in `.secondary` style (paused-state presentation).
  var dimmed: Bool = false

  /// Conservative scale keeps the decorative bar from growing as fast as the text.
  @ScaledMetric(relativeTo: .caption2) private var barHeight: CGFloat = 4

  /// Fuel gauge under budget (full = healthy, empties as you spend);
  /// flips to a full deficit-color bar when over budget. When `dimmed` is true,
  /// renders a full-width `.secondary` capsule — the unified inactive-state
  /// presentation (see `BudgetInactiveReason`) used for preStart, paused, and
  /// postEnd budgets where the fraction-driven render would be misleading.
  var body: some View {
    GeometryReader { geo in
      ZStack(alignment: .leading) {
        Capsule()
          .fill(Color.secondary.opacity(0.12))
        Capsule()
          .fill(dimmed ? Color.secondary : (isOverBudget ? Color.moneyDeficit : Color("AccentColor")))
          .frame(width: dimmed || isOverBudget ? geo.size.width : geo.size.width * remainingFraction)
      }
    }
    .frame(height: barHeight)
    // Intentionally hidden from assistive technologies: remaining amount, period,
    // and over-budget state are surfaced on parent accessibility labels instead.
    .accessibilityHidden(true)
  }
}

// MARK: - Preview

#Preview("Active vs dimmed") {
  VStack(alignment: .leading, spacing: 24) {
    VStack(alignment: .leading, spacing: 6) {
      Text(verbatim: "Active · 62% remaining")
        .font(.caption)
      RemainingBar(remainingFraction: 0.62, isOverBudget: false)
    }
    VStack(alignment: .leading, spacing: 6) {
      Text(verbatim: "Active · over budget")
        .font(.caption)
      RemainingBar(remainingFraction: 0, isOverBudget: true)
    }
    VStack(alignment: .leading, spacing: 6) {
      Text(verbatim: "Dimmed · full width (inactive presentation)")
        .font(.caption)
      RemainingBar(remainingFraction: 0.62, isOverBudget: false, dimmed: true)
    }
  }
  .padding()
}
