import SwiftUI

// MARK: - CarryOverChip

struct CarryOverChip: View {
  let amount: Decimal
  let currencyCode: String
  var display: CurrencyDisplayPreference = .symbol
  /// When `true`, the chip's foreground value is rendered in `.secondary` style
  /// (the paused-state presentation). The background capsule tint is unchanged.
  var dimmed: Bool = false

  @ScaledMetric(relativeTo: .footnote) private var chipSpacing: CGFloat = 3
  @ScaledMetric(relativeTo: .footnote) private var chipHPadding: CGFloat = 6
  @ScaledMetric(relativeTo: .footnote) private var chipVPadding: CGFloat = 3

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
    }
    .font(.footnote)
    .fontWeight(.medium)
    .foregroundStyle(dimmedStyle(chipForeground, when: dimmed))
    .padding(.horizontal, chipHPadding)
    .padding(.vertical, chipVPadding)
    .background(Capsule().fill(chipBackground))
    // Collapse the icon + amount + "carry-over" word into a single
    // VoiceOver static-text element with the explicit composed label.
    // Without this, each child Text/Image is its own VO element and
    // `.accessibilityLabel(...)` does not coalesce them.
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityLabel)
  }

  private var chipForeground: Color {
    amount < 0 ? Color("ChipDeficitForeground") : Color("ChipSurplusForeground")
  }

  private var chipBackground: Color {
    amount < 0 ? Color("ChipDeficitBackground") : Color("ChipSurplusBackground")
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
#Preview("Surplus – Dark") { chipPreview(CarryOverChip(amount: 42.50, currencyCode: "USD")).preferredColorScheme(.dark) }
#Preview("Deficit – Dark") { chipPreview(CarryOverChip(amount: -18.75, currencyCode: "USD")).preferredColorScheme(.dark) }
#Preview("Zero – Dark") { chipPreview(CarryOverChip(amount: 0, currencyCode: "USD")).preferredColorScheme(.dark) }
