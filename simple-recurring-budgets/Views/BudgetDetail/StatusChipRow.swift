import SwiftUI

// MARK: - StatusChipRow

/// Chip row shared by `BudgetRowView` (list) and the `BudgetDetailView` header: optional
/// `InactiveStatusChip` and `CarryOverChip`, plus a trailing `@ViewBuilder` slot for
/// surface-specific controls. `ViewThatFits` stacks vertically when the chips overflow
/// (large Dynamic Type). Owns only between-chip spacing; the parent sets top padding.
struct StatusChipRow<Trailing: View>: View {
  /// When non-nil, shows an `InactiveStatusChip` and dims the `CarryOverChip`.
  let inactiveReason: BudgetInactiveReason?
  let isCarryOverEnabled: Bool
  let carryOverAmount: Decimal
  let currencyCode: String
  var currencyDisplay: CurrencyDisplayPreference = .symbol
  /// Top padding when the row has content; zero by default so an empty row adds no layout.
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

#if DEBUG
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

  #Preview("Paused + carry-over at xxxLarge") {
    rowPreview(
      StatusChipRow(
        inactiveReason: .paused(since: PreviewDates.pausedSince),
        isCarryOverEnabled: true,
        carryOverAmount: 42.50,
        currencyCode: "USD"
      )
    )
    .dynamicTypeSize(.xxxLarge)
  }
#endif
