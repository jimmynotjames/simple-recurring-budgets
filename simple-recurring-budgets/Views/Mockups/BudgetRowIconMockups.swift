import SwiftData
import SwiftUI

// Design exploration for F-4.03 (per-budget icon). Self-contained — does not
// modify the production `BudgetRowView`. Two previews:
//   1. Standalone mock of layout "D · Inline Adjacent · Colored".
//   2. A copy of the real `BudgetRowView` body with the icon spliced inline
//      next to the budget name, rendered against seeded preview data so it
//      reads against the same building blocks the real screen uses.
// Delete or fold into BudgetsView.swift once a direction is chosen.

// MARK: - Mock data

private struct MockBudget: Identifiable {
  let id = UUID()
  let name: String
  let symbol: String
  let tint: Color
  let remaining: Int
  let allocation: Int
  let periodLabel: String
  let carryOver: Int?
}

private extension MockBudget {
  static let samples: [MockBudget] = [
    .init(
      name: "Food", symbol: "fork.knife",
      tint: Color(red: 0.78, green: 0.52, blue: 0.46),
      remaining: 12, allocation: 25, periodLabel: "today",
      carryOver: 4
    ),
    .init(
      name: "Groceries", symbol: "cart",
      tint: Color(red: 0.55, green: 0.68, blue: 0.55),
      remaining: 62, allocation: 100, periodLabel: "this week",
      carryOver: -8
    ),
    .init(
      name: "Coffee", symbol: "cup.and.saucer",
      tint: Color(red: 0.58, green: 0.46, blue: 0.40),
      remaining: 3, allocation: 7, periodLabel: "today",
      carryOver: nil
    ),
    .init(
      name: "Clothes", symbol: "tshirt",
      tint: Color(red: 0.45, green: 0.62, blue: 0.65),
      remaining: 80, allocation: 100, periodLabel: "this week",
      carryOver: 12
    ),
    .init(
      name: "Beauty", symbol: "sparkles",
      tint: Color(red: 0.66, green: 0.58, blue: 0.72),
      remaining: 45, allocation: 75, periodLabel: "this week",
      carryOver: nil
    ),
  ]
}

// MARK: - Shared mock subviews

private struct RemainingSummaryMock: View {
  let remaining: Int
  let allocation: Int
  let periodLabel: String

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 4) {
      Text("$\(remaining)")
        .font(.title3.weight(.semibold))
        .monospacedDigit()
        .foregroundStyle(.primary)
      Text("of $\(allocation) \(periodLabel)")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
  }
}

private struct CarryOverChipMock: View {
  let amount: Int

  var body: some View {
    let isDeficit = amount < 0
    let absText = "$\(abs(amount))"
    Text(isDeficit ? "\(absText) behind" : "\(absText) ahead")
      .font(.caption)
      .foregroundStyle(
        isDeficit
          ? Color(red: 0.62, green: 0.34, blue: 0.34)
          : Color(red: 0.34, green: 0.52, blue: 0.42)
      )
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .background(Capsule().fill(Color.secondary.opacity(0.10)))
  }
}

private struct PlusButtonMock: View {
  var body: some View {
    Image(systemName: "plus.circle.fill")
      .font(.largeTitle)
      .foregroundStyle(.tint)
      .frame(minWidth: 60, maxWidth: 60, minHeight: 44)
      .accessibilityLabel("Add expense")
  }
}

// MARK: - Layout D · Inline adjacent (colored)

// Symbol sits next to the budget name as a subordinate glyph; no leading
// column. Preserves today's row structure and the number's visual primacy.

private struct InlineAdjacentRow: View {
  let budget: MockBudget

  var body: some View {
    HStack(alignment: .center, spacing: 0) {
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 6) {
          Image(systemName: budget.symbol)
            .font(.footnote)
            .foregroundStyle(budget.tint)
          Text(budget.name)
            .font(.body)
            .foregroundStyle(.primary)
        }
        RemainingSummaryMock(
          remaining: budget.remaining,
          allocation: budget.allocation,
          periodLabel: budget.periodLabel
        )
        if let carryOver = budget.carryOver {
          CarryOverChipMock(amount: carryOver).padding(.top, 2)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      PlusButtonMock()
    }
    .padding(.vertical, 8)
  }
}

// MARK: - Mock list wrapper

private struct MockBudgetsList: View {
  var body: some View {
    NavigationStack {
      List(MockBudget.samples) { budget in
        InlineAdjacentRow(budget: budget)
      }
      #if os(iOS)
      .listStyle(.insetGrouped)
      #else
      .listStyle(.inset)
      #endif
      .navigationTitle("Budgets")
    }
    .tint(Color(red: 0.42, green: 0.55, blue: 0.55))
  }
}

// MARK: - Inline-icon splice for the real BudgetRowView

// Copied from BudgetsView.swift::BudgetRowView with one change: the budget
// name now sits in an HStack alongside an SF Symbol tinted per budget. All
// other elements (`BudgetRemainingSummary`, `StatusChipRow`, lifecycle
// task/onChange wiring, accessibility plumbing, +button) are reused verbatim
// so the preview reflects the production row's real behavior, not a mock.
//
// Keep in sync with `BudgetRowView` when iterating. Discard when this design
// is either adopted (icon param added to the real row) or rejected.

private struct BudgetRowViewWithInlineIcon: View {
  let budget: Budget
  let iconSymbol: String
  let iconTint: Color

  @Environment(AppSettings.self) private var settings
  @Environment(Router.self) private var router
  @Environment(\.scenePhase) private var scenePhase
  @State private var lifecycle: BudgetLifecycleResult?

  private var inactiveReason: BudgetInactiveReason? {
    guard let lifecycle else { return nil }
    return BudgetInactiveReason.from(lifecycle: lifecycle, budget: budget)
  }

  @ScaledMetric(relativeTo: .headline) private var rowSpacing: CGFloat = 10
  @ScaledMetric(relativeTo: .caption) private var chipTopSpacing: CGFloat = 16
  @ScaledMetric(relativeTo: .body) private var rowVerticalPadding: CGFloat = 8

  private var isSpecificDates: Bool {
    budget.periodEnum == .specificDates
  }

  private var remaining: Decimal {
    lifecycle?.remaining ?? 0
  }

  var body: some View {
    HStack(alignment: .center, spacing: 0) {
      VStack(alignment: .leading, spacing: 0) {
        Button {
          router.path.append(.budgetDetail(budget))
        } label: {
          VStack(alignment: .leading, spacing: rowSpacing) {
            // The single splice: icon sits inline with the budget name.
            HStack(spacing: 6) {
              Image(systemName: iconSymbol)
                .font(.footnote)
                .foregroundStyle(iconTint)
              Text(budget.name)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            }

            BudgetRemainingSummary(
              remaining: remaining,
              allocation: budget.currentAllocation,
              periodDisplayLabel: budget.periodDisplayLabel,
              currencyCode: budget.currencyCode,
              currencyDisplay: settings.currencyDisplay,
              inactiveReason: inactiveReason
            )
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(BudgetRemainingSummary.accessibilityLabel(
          budgetName: budget.name,
          remaining: remaining,
          allocation: budget.currentAllocation,
          isSpecificDates: isSpecificDates,
          periodInlineLabel: budget.periodInlineLabel,
          currencyCode: budget.currencyCode,
          currencyDisplay: settings.currencyDisplay,
          inactiveReason: inactiveReason
        ))

        StatusChipRow(
          inactiveReason: inactiveReason,
          isCarryOverEnabled: budget.isCarryOverEnabled && !isSpecificDates,
          carryOverAmount: lifecycle?.carryOverAmount ?? 0,
          currencyCode: budget.currencyCode,
          currencyDisplay: settings.currencyDisplay,
          topSpacing: chipTopSpacing
        )
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      Button {
        router.sheet = .addExpense(budget)
      } label: {
        Image(systemName: "plus.circle.fill")
          .font(.largeTitle)
      }
      .buttonStyle(.plain)
      .foregroundStyle(.tint)
      .padding(.leading, 16)
      .frame(minWidth: 60, maxWidth: 60, minHeight: 44)
      .contentShape(Rectangle())
    }
    .padding(.vertical, rowVerticalPadding)
    .task(id: budget.persistentModelID) {
      lifecycle = BudgetLifecycleService.result(for: budget)
    }
    .onChange(of: scenePhase) { _, newPhase in
      guard newPhase == .active else { return }
      lifecycle = BudgetLifecycleService.result(for: budget)
    }
    .onChange(of: budget.lastModified) {
      lifecycle = BudgetLifecycleService.result(for: budget)
    }
  }
}

/// Per-budget icon mapping for the real-data preview. Keyed on the seeded
/// `DebugData` budget names so each row gets a visually distinct treatment.
/// Falls back to a neutral circle for any unmapped name.
private enum SeededBudgetIcon {
  static func lookup(for name: String) -> (symbol: String, tint: Color) {
    switch name {
    case "Daily – Default":
      ("fork.knife", Color(red: 0.78, green: 0.52, blue: 0.46))
    case "Weekly – Groceries (EUR)":
      ("cart", Color(red: 0.55, green: 0.68, blue: 0.55))
    case "Daily – Surplus Carry-Over":
      ("cup.and.saucer", Color(red: 0.58, green: 0.46, blue: 0.40))
    case "Daily – Paused":
      ("tshirt", Color(red: 0.45, green: 0.62, blue: 0.65))
    case "Monthly – Deficit Carry-Over":
      ("sparkles", Color(red: 0.66, green: 0.58, blue: 0.72))
    case "Biweekly – Household Stipend":
      ("house", Color(red: 0.55, green: 0.55, blue: 0.65))
    case "Daily – Never Resets (JPY)":
      ("yensign.circle", Color(red: 0.60, green: 0.55, blue: 0.45))
    case "Weekly – Never Resets":
      ("calendar", Color(red: 0.50, green: 0.60, blue: 0.55))
    case "Daily – Pre-start":
      ("clock", Color(red: 0.55, green: 0.55, blue: 0.60))
    case "Weekly – Post-end":
      ("flag.checkered", Color(red: 0.55, green: 0.50, blue: 0.55))
    default:
      ("circle", .secondary)
    }
  }
}

private struct RealBudgetsListWithInlineIcon: View {
  @Query(sort: \Budget.sortOrder) private var budgets: [Budget]

  var body: some View {
    NavigationStack {
      List {
        ForEach(budgets) { budget in
          let icon = SeededBudgetIcon.lookup(for: budget.name)
          BudgetRowViewWithInlineIcon(
            budget: budget,
            iconSymbol: icon.symbol,
            iconTint: icon.tint
          )
          .listRowBackground(Color("CellBackground"))
        }
      }
      #if os(iOS)
      .listStyle(.insetGrouped)
      #else
      .listStyle(.inset)
      #endif
      .scrollContentBackground(.hidden)
      .navigationTitle("Budgets")
    }
    .appBackground()
    .tint(Color("AccentColor"))
  }
}

// MARK: - Previews

#Preview("D · Inline Adjacent · Colored (mock)") {
  MockBudgetsList()
}

#Preview("Real BudgetRow + inline icon (colored)") {
  RealBudgetsListWithInlineIcon()
    .modelContainer(PreviewContainer.make())
    .environment(Router())
    .environment(AppSettings())
    .environment(SyncStatus(containerBacking: .cloudKit, accountStatus: .available))
}
