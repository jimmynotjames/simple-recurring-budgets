//
//  BudgetsView.swift
//  simple-recurring-budgets
//

import SwiftUI
import SwiftData

// MARK: - BudgetsView

struct BudgetsView: View {
    @Query(sort: \Budget.sortOrder) private var budgets: [Budget]
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var context

    var body: some View {
        Group {
            if budgets.isEmpty {
                emptyStateView
            } else {
                populatedListView
            }
        }
        .navigationTitle(String(
            localized: "budgets.navigationTitle",
            defaultValue: "Budgets",
            comment: "Navigation bar title for the budgets list screen"
        ))
        .appBackground()
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                Button {
                    router.sheet = .settings
                } label: {
                    Label(
                        String(
                            localized: "toolbar.settings.label",
                            defaultValue: "Settings",
                            comment: "Label for the Settings toolbar button; also used as its VoiceOver label"
                        ),
                        systemImage: "gearshape"
                    )
                }
                .accessibilityHint(String(
                    localized: "toolbar.settings.accessibilityHint",
                    defaultValue: "Opens app settings",
                    comment: "VoiceOver hint for the Settings toolbar button"
                ))

                // Only show the Edit button when there are rows to reorder.
                if !budgets.isEmpty {
                    EditButton()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.sheet = .addBudget
                } label: {
                    Image(systemName: "plus")
                        .fontWeight(.semibold)
                }
                .accessibilityLabel(String(
                    localized: "toolbar.addBudget.accessibilityLabel",
                    defaultValue: "Add budget",
                    comment: "VoiceOver label for the Add Budget toolbar button"
                ))
                .accessibilityHint(String(
                    localized: "toolbar.addBudget.accessibilityHint",
                    defaultValue: "Opens add budget form",
                    comment: "VoiceOver hint for the Add Budget toolbar button"
                ))
            }
        }
    }

    // MARK: - Private views

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label(
                String(
                    localized: "budgets.empty.title",
                    defaultValue: "No budgets yet",
                    comment: "Empty-state title on the Budgets screen when no budgets exist"
                ),
                systemImage: "tray"
            )
        } description: {
            Text(String(
                localized: "budgets.empty.description",
                defaultValue: "Create your first recurring budget to start tracking what you spend each day, week, biweek, or month.",
                comment: "Empty-state description on the Budgets screen"
            ))
        } actions: {
            Button {
                router.sheet = .addBudget
            } label: {
                Text(String(
                    localized: "budgets.empty.createBudget",
                    defaultValue: "Create a budget",
                    comment: "Primary CTA button on the empty-state of the Budgets screen"
                ))
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var populatedListView: some View {
        List {
            ForEach(budgets) { budget in
                BudgetRowView(budget: budget)
                    .listRowBackground(Color("CellBackground"))
            }
            .onMove(perform: move)
        }
        .listStyle(.automatic)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Handlers

    /// Reorders budgets after a user drag-to-reorder gesture.
    ///
    /// Rewrites `sortOrder` densely over the new order (0..<count).
    /// Only mutates — and bumps `lastModified` on — rows whose `sortOrder` actually changed.
    /// Batches all writes into a single `context.save()`.
    private func move(from source: IndexSet, to destination: Int) {
        var reordered = budgets
        reordered.move(fromOffsets: source, toOffset: destination)
        let now = Date()
        for (index, budget) in reordered.enumerated() where budget.sortOrder != index {
            budget.sortOrder = index
            budget.lastModified = now
        }
        try? context.save()
    }

}

// MARK: - BudgetRowView

struct BudgetRowView: View {
    let budget: Budget

    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(Router.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var lifecycle: BudgetLifecycleResult?

    // Scale spacing and padding with the user's preferred text size,
    // except for add-expense button, which is fixed.
    @ScaledMetric(relativeTo: .headline) private var rowSpacing: CGFloat = 7
    @ScaledMetric(relativeTo: .callout) private var amountSpacing: CGFloat = 6
    @ScaledMetric(relativeTo: .caption) private var chipTopSpacing: CGFloat = 12
    @ScaledMetric(relativeTo: .body) private var rowVerticalPadding: CGFloat = 6

    private var period: BudgetPeriod {
        BudgetPeriod(rawValue: budget.period) ?? .daily
    }

    private var remaining: Decimal {
        lifecycle?.remaining ?? 0
    }

    /// Fraction of the allocation still available: 1.0 = full allocation remaining,
    /// 0.0 = nothing left. Clamped to [0, 1]; over-budget collapses to 0 and is
    /// signalled separately via `isOverBudget` on `RemainingBar`.
    private var remainingFraction: Double {
        guard budget.allocation > 0 else { return 0 }
        let ratio = remaining / budget.allocation
        return max(0, min(1, (ratio as NSDecimalNumber).doubleValue))
    }

    private var amountLayout: AnyLayout {
        dynamicTypeSize >= .xxxLarge
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: amountSpacing))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: amountSpacing))
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // Outer VStack groups the tappable row content with the carry-over chip.
            // The chip lives outside the Button so VoiceOver treats it as a separate
            // static-text element rather than a non-activatable nested element.
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    router.path.append(.budgetDetail(budget))
                } label: {
                    VStack(alignment: .leading, spacing: rowSpacing) {
                        // Line 1: Budget name
                        Text(budget.name)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        // Line 2: Remaining amount + period
                        // Stacks vertically at accessibility1+ to give the amount more room.
                        amountLayout {
                            Text(remaining.formatted(currencyCode: budget.currencyCode, display: settings.currencyDisplay))
                                .font(.largeTitle)
                                .monospacedDigit()
                                .foregroundStyle(remaining >= 0 ? Color.primary : Color.moneyDeficit)
                                .lineLimit(1)

                            Text(period.listLabel)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }

                        // Line 3: Indicator bar (hidden from assistive technologies;
                        // over-budget state is surfaced in the accessibility label instead).
                        RemainingBar(remainingFraction: remainingFraction, isOverBudget: remaining < 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(rowAccessibilityLabel)
                .accessibilityHint(String(
                    localized: "budget.row.accessibilityHint",
                    defaultValue: "Opens budget details",
                    comment: "VoiceOver hint for a budget row; describes what happens when the user activates it"
                ))

                // Line 4: Carry-over chip — separate from the button so VoiceOver
                // can read it as a distinct static-text element.
                if budget.isCarryOverEnabled {
                    CarryOverChip(
                        amount: lifecycle?.carryOverAmount ?? budget.carryOverAmount,
                        currencyCode: budget.currencyCode,
                        display: settings.currencyDisplay
                    )
                    .padding(.top, chipTopSpacing)
                    .accessibilityAddTraits(.isStaticText)
                }
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
            // Keep right button fixed size to allow more room for text as Dynamic Type sizes grow.
            .frame(minWidth: 60, maxWidth: 60, minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityLabel(
                String(
                    localized: "budget.row.addExpense.accessibilityLabel",
                    defaultValue: "Add expense for \(budget.name)",
                    comment: "VoiceOver label for the add-expense button in a budget row; argument is the budget name"
                )
            )
            .accessibilityHint(String(
                localized: "budget.row.addExpense.accessibilityHint",
                defaultValue: "Opens add expense form",
                comment: "VoiceOver hint for the add-expense button in a budget row"
            ))
        }
        .padding(.vertical, rowVerticalPadding)
        .task(id: budget.persistentModelID) {
            lifecycle = BudgetLifecycleService.refreshAndSave(
                budget, settings: settings, context: context
            )
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            lifecycle = BudgetLifecycleService.refreshAndSave(
                budget, settings: settings, context: context
            )
        }
    }

    /// Builds the VoiceOver label for the row button, including period and — when the
    /// budget is exceeded — an explicit "over budget" signal instead of a negative amount.
    /// Intentionally set as computed var to handle hot-swapping localizations.
    private var rowAccessibilityLabel: String {
        if remaining < 0 {
            return String(
                localized: "budget.row.accessibilityLabel.overBudget",
                defaultValue: "\(budget.name), \((-remaining).formatted(currencyCode: budget.currencyCode, display: settings.currencyDisplay)) over budget this \(period.inlineLabel) period",
                comment: "VoiceOver label for an over-budget row; arguments are the budget name, the positive overage amount, and the period name"
            )
        }
        return String(
            localized: "budget.row.accessibilityLabel",
            defaultValue: "\(budget.name), \(remaining.formatted(currencyCode: budget.currencyCode, display: settings.currencyDisplay)) remaining this \(period.inlineLabel) period",
            comment: "VoiceOver label for a budget row; states the budget name, remaining amount, and period"
        )
    }
}

// MARK: - RemainingBar

private struct RemainingBar: View {
    let remainingFraction: Double   // 0.0–1.0, already clamped; see BudgetRowView.remainingFraction
    let isOverBudget: Bool

    // Conservative scale keeps the decorative bar from growing as fast as the text.
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
        // and over-budget state are all surfaced in the parent row's accessibilityLabel,
        // making the bar decorative/redundant noise for VoiceOver users.
        .accessibilityHidden(true)
    }
}

// MARK: - Preview

private struct BudgetsPreview: View {
    var empty: Bool = false

    var body: some View {
        NavigationStack {
            BudgetsView()
        }
        .modelContainer(empty ? InMemoryModelContainer.makeEmpty() : PreviewContainer.make())
        .environment(Router())
        .environment(AppSettings())
        .environment(SyncStatus(containerBacking: .cloudKit, accountStatus: .available))
    }
}

#Preview("Light Mode") { BudgetsPreview() }
#Preview("Dark Mode") { BudgetsPreview().preferredColorScheme(.dark) }
// Just below reformatting threshold.
#Preview("xxLarge") { BudgetsPreview().dynamicTypeSize(.xxLarge) }
// Just at reformatting threshold. (Changes from horizontal stack to vertical).
#Preview("xxxLarge") { BudgetsPreview().dynamicTypeSize(.xxxLarge) }
#Preview("Empty state") { BudgetsPreview(empty: true) }
