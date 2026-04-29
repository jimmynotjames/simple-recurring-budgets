import SwiftUI

// MARK: - CarryOverChip

struct CarryOverChip: View {
  let amount: Decimal
  let currencyCode: String
  var display: CurrencyDisplayPreference = .symbol

  @Environment(\.colorSchemeContrast) private var colorSchemeContrast

  @ScaledMetric(relativeTo: .caption) private var chipSpacing: CGFloat = 3
  @ScaledMetric(relativeTo: .caption) private var chipHPadding: CGFloat = 6
  @ScaledMetric(relativeTo: .caption) private var chipVPadding: CGFloat = 3

  private var carryOverDisplay: CarryOverDisplay {
    CarryOverFormatter.display(amount, currencyCode: currencyCode, display: display)
  }

  var body: some View {
    HStack(spacing: chipSpacing) {
      if amount != 0 {
        Image(systemName: amount > 0 ? "arrow.up" : "arrow.down")
      }
      Text(carryOverDisplay.amount)
      Text(String(localized: "carryOver.label", defaultValue: "carry-over", comment: "Fixed label shown in the carry-over chip on the budgets list"))
        .foregroundStyle(chipForeground.opacity(colorSchemeContrast == .increased ? 1.0 : 0.8))
    }
    .font(.caption)
    .fontWeight(.medium)
    .foregroundStyle(chipForeground)
    .padding(.horizontal, chipHPadding)
    .padding(.vertical, chipVPadding)
    .background(Capsule().fill(chipBackground))
    .accessibilityLabel(accessibilityLabel)
  }

  private var chipForeground: Color {
    amount < 0 ? Color.moneyDeficit : Color.moneySurplus
  }

  private var chipBackground: Color {
    let opacity = colorSchemeContrast == .increased ? 0.05 : 0.15
    return amount < 0 ? Color.moneyDeficit.opacity(opacity) : Color.moneySurplus.opacity(opacity)
  }

  private var accessibilityLabel: String {
    if amount > 0 {
      return String(
        localized: "carryOver.accessibilityLabel.surplus",
        defaultValue: "\(carryOverDisplay.amount) surplus carry-over",
        comment: "VoiceOver label for a surplus carry-over chip; argument is the formatted currency amount"
      )
    }
    if amount < 0 {
      return String(
        localized: "carryOver.accessibilityLabel.deficit",
        defaultValue: "\(carryOverDisplay.amount) deficit carry-over",
        comment: "VoiceOver label for a deficit carry-over chip; argument is the formatted currency amount"
      )
    }
    return String(
      localized: "carryOver.accessibilityLabel.zero",
      defaultValue: "zero carry-over",
      comment: "VoiceOver label for a carry-over chip showing zero balance"
    )
  }
}

// MARK: - Preview

private func chipPreview(_ chip: some View) -> some View {
  VStack {
    chip.padding()
    Spacer()
  }
}

#Preview("Surplus") { chipPreview(CarryOverChip(amount: 42.50, currencyCode: "USD")) }
#Preview("Deficit") { chipPreview(CarryOverChip(amount: -18.75, currencyCode: "USD")) }
#Preview("Zero") { chipPreview(CarryOverChip(amount: 0, currencyCode: "USD")) }
