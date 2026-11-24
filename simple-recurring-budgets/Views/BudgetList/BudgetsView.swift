import SwiftData
import SwiftUI

// MARK: - BudgetsView

struct BudgetsView: View {
  @Query(sort: \Budget.sortOrder) private var budgets: [Budget]
  @Environment(Router.self) private var router
  @Environment(\.modelContext) private var context
  @Environment(\.analytics) private var analytics
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  /// Save-error alert state for the reorder save.
  @State private var saveError: SaveErrorState?

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
    .saveErrorAlert($saveError)
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
        // iOS 26 draws bar buttons monochrome and ignores the asset-catalog global accent;
        // the explicit tint restores the brand accent (WCAG AA). Same on all bar buttons.
        .tint(.accentColor)
        .accessibilityHint(String(
          localized: "toolbar.settings.accessibilityHint",
          defaultValue: "Opens app settings",
          comment: "VoiceOver hint for the Settings toolbar button"
        ))
        // Locale-invariant test handle (= localization key) so UI tests navigate in any
        // language. Sole consumer: LocalizationScreenshotCapture
        // (scripts/translation-accessibility-size-check/); update it if this changes.
        .accessibilityIdentifier("toolbar.settings.label")
        // Edit only when there are rows to reorder.
        if !budgets.isEmpty {
          EditButton()
            .tint(.accentColor)
        }
      }
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          router.sheet = .addBudget
        } label: {
          HStack(spacing: 4) {
            Image(systemName: "plus")
              .fontWeight(.semibold)
            // Hidden at accessibility sizes: the HStack clips in the fixed-height toolbar at
            // Accessibility Extra Large and above. The .accessibilityLabel below covers VoiceOver.
            if !dynamicTypeSize.isAccessibilitySize {
              Text(String(
                localized: "toolbar.addBudget.label",
                defaultValue: "New Budget",
                comment: "Label for the Add Budget toolbar button"
              ))
              .lineLimit(1)
            }
          }
        }
        .tint(.accentColor)
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
        // Test handle; see toolbar.settings.label above.
        .accessibilityIdentifier("toolbar.addBudget.accessibilityLabel")
      }
    }
  }

  // MARK: - Private views

  private var emptyStateView: some View {
    // Custom rather than ContentUnavailableView: the system component imposes an
    // undocumented line limit on its description that clips the long string on some iOS
    // versions. Don't swap it back.
    VStack(spacing: 16) {
      Image(systemName: "tray")
        .font(.system(size: 56))
        .foregroundStyle(.secondary)
      VStack(spacing: 4) {
        Text(String(
          localized: "budgets.empty.title",
          defaultValue: "No budgets yet",
          comment: "Empty-state title on the Budgets screen when no budgets exist"
        ))
        .font(.title2.bold())
        .lineLimit(1)
        .allowsTightening(true)
        .fixedSize(horizontal: false, vertical: true)
        Text(String(
          localized: "budgets.empty.description",
          defaultValue: "Create your first recurring budget to start tracking what you spend each day, week, biweek, or month.",
          comment: "Empty-state description on the Budgets screen"
        ))
        .font(.subheadline)
        .foregroundStyle(.readableSecondary)
        .multilineTextAlignment(.center)
        .lineLimit(nil)
        .fixedSize(horizontal: false, vertical: true)
      }
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
      .tint(Color.accentFill)
      .controlSize(.large)
    }
    .padding(.horizontal, 32)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
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

  /// Applies the `BudgetReorderService` rewrite after a drag, then saves once.
  private func move(from source: IndexSet, to destination: Int) {
    BudgetReorderService.applyMove(
      budgets: budgets,
      fromOffsets: source,
      toOffset: destination,
      now: Date()
    )
    do {
      try context.saveChanges(operation: .reorder, analytics: analytics)
      saveError.clear()
    } catch let error as PersistenceError {
      saveError.setForFailure(error, retry: { move(from: source, to: destination) })
    } catch {
      // saveChanges only throws PersistenceError; exhaustive catch for safety.
    }
  }
}

// MARK: - BudgetRowView

struct BudgetRowView: View {
  let budget: Budget

  @Environment(AppSettings.self) private var settings
  @Environment(Router.self) private var router
  @Environment(\.scenePhase) private var scenePhase
  @State private var lifecycle: BudgetLifecycleResult?

  /// Inactive-presentation reason (`nil` when active); drives the dimmed amount,
  /// full-width secondary bar, and `InactiveStatusChip`.
  private var inactiveReason: BudgetInactiveReason? {
    guard let lifecycle else { return nil }
    return BudgetInactiveReason.from(lifecycle: lifecycle, budget: budget)
  }

  // Spacing scales with text size; the add-expense button is fixed.
  @ScaledMetric(relativeTo: .headline) private var rowSpacing: CGFloat = 10
  @ScaledMetric(relativeTo: .caption) private var chipTopSpacing: CGFloat = 16
  @ScaledMetric(relativeTo: .body) private var rowVerticalPadding: CGFloat = 8

  private var isSpecificDates: Bool {
    budget.periodEnum == .specificDates
  }

  private var remaining: Decimal {
    lifecycle?.remaining ?? 0
  }

  /// Name with an optional `icon` emoji prefix. The icon is a separate leading view so it
  /// mirrors in RTL; its trailing space is the gap, hence `spacing` 0. Decorative:
  /// VoiceOver reads the explicit `.accessibilityLabel`, which omits it.
  private var nameText: some View {
    HStack(alignment: .firstTextBaseline, spacing: 0) {
      if let icon = budget.icon, !icon.isEmpty {
        Text(verbatim: "\(icon) ")
      }
      Text(budget.name)
    }
  }

  var body: some View {
    HStack(alignment: .center, spacing: 0) {
      // The chip row sits outside the Button so VoiceOver reads it as a separate element,
      // not a non-activatable nested one.
      VStack(alignment: .leading, spacing: 0) {
        Button {
          router.path.append(.budgetDetail(budget.id))
        } label: {
          VStack(alignment: .leading, spacing: rowSpacing) {
            nameText
              .font(.body)
              .foregroundStyle(.primary)
              .lineLimit(2)
              .multilineTextAlignment(.leading)

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
        .accessibilityHint(String(
          localized: "budget.row.accessibilityHint",
          defaultValue: "Opens budget details",
          comment: "VoiceOver hint for a budget row; describes what happens when the user activates it"
        ))

        // Outside the Button so VoiceOver doesn't fold the chips into its label.
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
        router.sheet = .addExpense(budget.id)
      } label: {
        Image(systemName: "plus.circle.fill")
          .font(.largeTitle)
      }
      .buttonStyle(.plain)
      .foregroundStyle(.tint)
      .padding(.leading, 16)
      // Fixed size leaves more room for text as Dynamic Type grows.
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
      // Test handle; see toolbar.settings.label above.
      .accessibilityIdentifier("budget.row.addExpense.accessibilityLabel")
    }
    .padding(.vertical, rowVerticalPadding)
    .task(id: budget.persistentModelID) {
      refreshLifecycle()
    }
    .onChange(of: scenePhase) { _, newPhase in
      guard newPhase == .active else { return }
      refreshLifecycle()
    }
    // Fires when the budget or any child changes, including a CloudKit merge that adds
    // expenses without bumping `budget.lastModified`. See `Budget.recomputeToken`.
    .onChange(of: budget.recomputeToken) {
      refreshLifecycle()
    }
    // Period boundaries passing while foregrounded: scenePhase/recomputeToken don't
    // fire at midnight.
    .onCalendarDayChange {
      refreshLifecycle()
    }
    // Week Starts On changed (Settings or iCloud KVS sync): weekly budgets re-grid.
    .onChange(of: settings.weekStartDay) {
      refreshLifecycle()
    }
  }

  private func refreshLifecycle() {
    lifecycle = BudgetLifecycleService.result(for: budget, weekStart: settings.weekStartDay)
  }
}

// MARK: - Preview

#if DEBUG
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

  // Seeded fixtures give a few budgets icons, so rows mix emoji-prefixed and name-only.
  #Preview("Light Mode") { BudgetsPreview() }
  #Preview("Dark Mode") { BudgetsPreview().preferredColorScheme(.dark) }
  // Just below reformatting threshold.
  #Preview("xxLarge") { BudgetsPreview().dynamicTypeSize(.xxLarge) }
  // At the reformatting threshold (horizontal → vertical stack).
  #Preview("xxxLarge") { BudgetsPreview().dynamicTypeSize(.xxxLarge) }
  #Preview("Empty state") { BudgetsPreview(empty: true) }
#endif
