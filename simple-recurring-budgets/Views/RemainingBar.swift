import SwiftUI

/// Decorative fuel-gauge bar under the remaining amount on budget surfaces.
///
/// Fraction is **0.0–1.0**, already clamped; when over budget, pass `isOverBudget: true`
/// so the bar fills in the deficit color instead of emptying in accent color.
struct RemainingBar: View {
  let remainingFraction: Double
  let isOverBudget: Bool

  /// Conservative scale keeps the decorative bar from growing as fast as the text.
  @ScaledMetric(relativeTo: .caption2) private var barHeight: CGFloat = 4

  /// Fuel gauge under budget (full = healthy, empties as you spend);
  /// flips to a full deficit-color bar when over budget.
  var body: some View {
    GeometryReader { geo in
      ZStack(alignment: .leading) {
        Capsule()
          .fill(Color.secondary.opacity(0.12))
        Capsule()
          .fill(isOverBudget ? Color.moneyDeficit : Color.accentColor)
          .frame(width: isOverBudget ? geo.size.width : geo.size.width * remainingFraction)
      }
    }
    .frame(height: barHeight)
    // Intentionally hidden from assistive technologies: remaining amount, period,
    // and over-budget state are surfaced on parent accessibility labels instead.
    .accessibilityHidden(true)
  }
}
