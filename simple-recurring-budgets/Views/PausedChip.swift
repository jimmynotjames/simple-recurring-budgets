import SwiftUI

// MARK: - PausedChip

/// Compact status chip shown on a `BudgetRowView` when the budget is paused.
///
/// Parallel to `CarryOverChip`: lives outside the row's tap target so VoiceOver
/// reads it as its own static-text element. The chip itself is the paused
/// indicator, so — unlike `CarryOverChip` — it has no `dimmed:` mode.
struct PausedChip: View {
  let pausedSince: Date

  @Environment(\.colorSchemeContrast) private var colorSchemeContrast

  @ScaledMetric(relativeTo: .caption) private var chipSpacing: CGFloat = 3
  @ScaledMetric(relativeTo: .caption) private var chipHPadding: CGFloat = 6
  @ScaledMetric(relativeTo: .caption) private var chipVPadding: CGFloat = 3

  private var formattedDate: String {
    pausedSince.formatted(date: .abbreviated, time: .omitted)
  }

  var body: some View {
    HStack(spacing: chipSpacing) {
      Image(systemName: "pause.circle.fill")
      Text(String(
        localized: "chip.paused.label.format",
        defaultValue: "Paused · \(formattedDate)",
        comment: "Compact chip shown on a budget row when paused; argument is the abbreviated date the budget was paused"
      ))
    }
    .font(.caption)
    .fontWeight(.medium)
    .foregroundStyle(.secondary)
    .padding(.horizontal, chipHPadding)
    .padding(.vertical, chipVPadding)
    .background(Capsule().fill(chipBackground))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(String(
      localized: "chip.paused.accessibilityLabel.format",
      defaultValue: "Paused since \(formattedDate)",
      comment: "VoiceOver label for the paused chip; argument is the abbreviated date the budget was paused"
    ))
  }

  private var chipBackground: Color {
    let opacity = colorSchemeContrast == .increased ? 0.05 : 0.15
    return Color.primary.opacity(opacity)
  }
}

// MARK: - Preview

#Preview("Default") {
  VStack(spacing: 12) {
    PausedChip(pausedSince: Date())
    PausedChip(pausedSince: Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date())
    Spacer()
  }
  .padding()
}

#Preview("Dark Mode") {
  PausedChip(pausedSince: Date())
    .padding()
    .preferredColorScheme(.dark)
}
