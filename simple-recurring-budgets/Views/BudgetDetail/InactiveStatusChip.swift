import SwiftUI

// MARK: - InactiveStatusChip

/// Compact status chip surfacing the reason a budget is not currently running.
///
/// Generalizes the previous `PausedChip` to three variants — `.preStart`,
/// `.paused`, `.postEnd` — sharing capsule styling, increased-contrast handling,
/// and Dynamic-Type-scaled padding. Each variant pairs an SF Symbol with a
/// localized "{Status} · {date}" label.
///
/// Lives outside the row's tap target so VoiceOver reads it as its own
/// static-text element. The chip itself is the inactive indicator, so — unlike
/// `CarryOverChip` — it has no `dimmed:` mode (it's always rendered in the
/// secondary foreground).
struct InactiveStatusChip: View {
  let reason: BudgetInactiveReason

  @ScaledMetric(relativeTo: .caption) private var chipSpacing: CGFloat = 3
  @ScaledMetric(relativeTo: .caption) private var chipHPadding: CGFloat = 6
  @ScaledMetric(relativeTo: .caption) private var chipVPadding: CGFloat = 3

  var body: some View {
    HStack(spacing: chipSpacing) {
      Image(systemName: systemImage)
      Text(label)
    }
    .font(.caption)
    .fontWeight(.medium)
    .foregroundStyle(Color.primary.opacity(0.6))
    .padding(.horizontal, chipHPadding)
    .padding(.vertical, chipVPadding)
    .background(Capsule().fill(chipBackground))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityLabel)
  }

  private var systemImage: String {
    switch reason {
    case .preStart: "calendar.badge.clock"
    case .paused: "pause.circle.fill"
    case .postEnd: "checkmark.circle"
    }
  }

  private var label: String {
    switch reason {
    case let .preStart(startDate):
      let formatted = startDate.formatted(date: .abbreviated, time: .omitted)
      return String(
        localized: "chip.inactive.preStart.label.format",
        defaultValue: "Starts \(formatted)",
        comment: "Compact chip shown on a budget row before the budget's start date; argument is the abbreviated start date"
      )
    case let .paused(since):
      let formatted = since.formatted(date: .abbreviated, time: .omitted)
      return String(
        localized: "chip.paused.label.format",
        defaultValue: "Paused · \(formatted)",
        comment: "Compact chip shown on a budget row when paused; argument is the abbreviated date the budget was paused"
      )
    case let .postEnd(endDate):
      let formatted = endDate.formatted(date: .abbreviated, time: .omitted)
      return String(
        localized: "chip.inactive.postEnd.label.format",
        defaultValue: "Ended \(formatted)",
        comment: "Compact chip shown on a budget row after the budget's end date; argument is the abbreviated end date"
      )
    }
  }

  private var accessibilityLabel: String {
    switch reason {
    case let .preStart(startDate):
      let formatted = startDate.formatted(date: .abbreviated, time: .omitted)
      return String(
        localized: "chip.inactive.preStart.accessibilityLabel.format",
        defaultValue: "Starts \(formatted)",
        comment: "VoiceOver label for the inactive (pre-start) chip; argument is the abbreviated start date"
      )
    case let .paused(since):
      let formatted = since.formatted(date: .abbreviated, time: .omitted)
      return String(
        localized: "chip.paused.accessibilityLabel.format",
        defaultValue: "Paused since \(formatted)",
        comment: "VoiceOver label for the paused chip; argument is the abbreviated date the budget was paused"
      )
    case let .postEnd(endDate):
      let formatted = endDate.formatted(date: .abbreviated, time: .omitted)
      return String(
        localized: "chip.inactive.postEnd.accessibilityLabel.format",
        defaultValue: "Ended \(formatted)",
        comment: "VoiceOver label for the inactive (post-end) chip; argument is the abbreviated end date"
      )
    }
  }

  private var chipBackground: Color {
    Color.primary.opacity(0.10)
  }
}

// MARK: - Preview

#if DEBUG
  private func chipStack() -> some View {
    VStack(alignment: .leading, spacing: 12) {
      InactiveStatusChip(reason: .preStart(startDate: PreviewDates.preStart))
      InactiveStatusChip(reason: .paused(since: PreviewDates.pausedSince))
      InactiveStatusChip(reason: .postEnd(endDate: PreviewDates.postEnd))
      Spacer()
    }
    .padding()
  }

  #Preview("Light Mode") { chipStack() }
  #Preview("Dark Mode") { chipStack().preferredColorScheme(.dark) }
#endif
