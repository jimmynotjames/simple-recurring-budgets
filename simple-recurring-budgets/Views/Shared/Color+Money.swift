import SwiftUI

extension Color {
  /// Negative money signals: over-budget remaining, over-budget bar fill, deficit
  /// carry-over chip. Aliases a dynamic system color (adapts to light/dark). High-contrast
  /// variants are not handled.
  static let moneyDeficit: Color = .orange

  /// Positive money signals: surplus carry-over chip. Same rationale and high-contrast
  /// caveat as `moneyDeficit`.
  static let moneySurplus: Color = .green
}
