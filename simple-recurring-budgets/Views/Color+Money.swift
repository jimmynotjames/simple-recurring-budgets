//
//  Color+Money.swift
//  simple-recurring-budgets
//

import SwiftUI

extension Color {
    /// Semantic color for negative money signals: over-budget remaining,
    /// over-budget usage bar fill, and deficit carry-over chip foreground/background.
    /// Aliases the dynamic system color so it auto-adapts to light/dark mode.
    /// Accessibility for high-contrast is intentionally unhandled for now.
    static let moneyDeficit: Color = .orange

    /// Semantic color for positive money signals: surplus carry-over chip
    /// foreground/background. Same dynamic-system-color rationale as `moneyDeficit`.
    /// Accessibility for high-contrast is intentionally unhandled for now.
    static let moneySurplus: Color = .green
}
