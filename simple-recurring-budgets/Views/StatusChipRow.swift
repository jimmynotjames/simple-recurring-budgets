import SwiftUI

// MARK: - StatusChipRow

/// Shared status-chip row used by `BudgetRowView` (Budgets list) and
/// `BudgetDetailView` header. Renders an optional `InactiveStatusChip` and an
/// optional `CarryOverChip`, with a trailing `@ViewBuilder` slot for
/// surface-specific controls (e.g. the detail screen's Reset Carry-Over button).
///
/// `ViewThatFits` drops the row to a vertical stack at large Dynamic Type when
/// the chips together (plus any trailing content) would exceed the available
/// width.
///
/// Owns only its internal between-chip spacing — the parent decides the
/// top padding to the surrounding row content.
struct StatusChipRow<Trailing: View>: View {
  /// When non-nil, drives an `InactiveStatusChip` for the matching reason and
  /// dims the `CarryOverChip`. See `BudgetInactiveReason`.
  let inactiveReason: BudgetInactiveReason?
  let isCarryOverEnabled: Bool
  let carryOverAmount: Decimal
  let currencyCode: String
  var currencyDisplay: CurrencyDisplayPreference = .symbol
  /// Top padding applied above the row when it has content. Zero by default so
  /// the component contributes no layout when it has nothing to show.
  var topSpacing: CGFloat = 0
  @ViewBuilder var trailing: () -> Trailing

  @ScaledMetric(relativeTo: .caption) private var chipSpacing: CGFloat = 6

  private var showsRow: Bool {
    inactiveReason != nil || isCarryOverEnabled
  }

  var body: some View {
    if showsRow {
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .center, spacing: chipSpacing) { chips }
        VStack(alignment: .leading, spacing: chipSpacing) { chips }
      }
      .padding(.top, topSpacing)
    }
  }

  @ViewBuilder
  private var chips: some View {
    if let reason = inactiveReason {
      InactiveStatusChip(reason: reason)
    }
    if isCarryOverEnabled {
      CarryOverChip(
        amount: carryOverAmount,
        currencyCode: currencyCode,
        display: currencyDisplay,
        dimmed: inactiveReason != nil
      )
    }
    trailing()
  }
}

extension StatusChipRow where Trailing == EmptyView {
  /// Convenience initializer for callers that don't need a trailing slot.
  init(
    inactiveReason: BudgetInactiveReason?,
    isCarryOverEnabled: Bool,
    carryOverAmount: Decimal,
    currencyCode: String,
    currencyDisplay: CurrencyDisplayPreference = .symbol,
    topSpacing: CGFloat = 0
  ) {
    self.init(
      inactiveReason: inactiveReason,
      isCarryOverEnabled: isCarryOverEnabled,
      carryOverAmount: carryOverAmount,
      currencyCode: currencyCode,
      currencyDisplay: currencyDisplay,
      topSpacing: topSpacing,
      trailing: { EmptyView() }
    )
  }
}

// MARK: - Preview

private func rowPreview(_ content: some View) -> some View {
  VStack(alignment: .leading, spacing: 16) {
    content
    Spacer()
  }
  .padding()
}

#Preview("Paused only") {
  rowPreview(
    StatusChipRow(
      inactiveReason: .paused(since: PreviewDates.pausedSince),
      isCarryOverEnabled: false,
      carryOverAmount: 0,
      currencyCode: "USD"
    )
  )
}

#Preview("Pre-start only") {
  rowPreview(
    StatusChipRow(
      inactiveReason: .preStart(startDate: PreviewDates.preStart),
      isCarryOverEnabled: false,
      carryOverAmount: 0,
      currencyCode: "USD"
    )
  )
}

#Preview("Post-end only") {
  rowPreview(
    StatusChipRow(
      inactiveReason: .postEnd(endDate: PreviewDates.postEnd),
      isCarryOverEnabled: false,
      carryOverAmount: 0,
      currencyCode: "USD"
    )
  )
}

#Preview("Carry-over only") {
  rowPreview(
    StatusChipRow(
      inactiveReason: nil,
      isCarryOverEnabled: true,
      carryOverAmount: 42.50,
      currencyCode: "USD"
    )
  )
}

#Preview("Paused + carry-over") {
  rowPreview(
    StatusChipRow(
      inactiveReason: .paused(since: PreviewDates.pausedSince),
      isCarryOverEnabled: true,
      carryOverAmount: -18.75,
      currencyCode: "USD"
    )
  )
}

#Preview("Pre-start + carry-over") {
  rowPreview(
    StatusChipRow(
      inactiveReason: .preStart(startDate: PreviewDates.preStart),
      isCarryOverEnabled: true,
      carryOverAmount: 12.00,
      currencyCode: "USD"
    )
  )
}

#Preview("Post-end + carry-over") {
  rowPreview(
    StatusChipRow(
      inactiveReason: .postEnd(endDate: PreviewDates.postEnd),
      isCarryOverEnabled: true,
      carryOverAmount: 0,
      currencyCode: "USD"
    )
  )
}

#Preview("With trailing Reset") {
  rowPreview(
    StatusChipRow(
      inactiveReason: nil,
      isCarryOverEnabled: true,
      carryOverAmount: 42.50,
      currencyCode: "USD"
    ) {
      Button("Reset") {}
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
  )
}

#Preview("Paused + carry-over + Reset at xxxLarge") {
  rowPreview(
    StatusChipRow(
      inactiveReason: .paused(since: PreviewDates.pausedSince),
      isCarryOverEnabled: true,
      carryOverAmount: 42.50,
      currencyCode: "USD"
    ) {
      Button("Reset") {}
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
  )
  .dynamicTypeSize(.xxxLarge)
}
