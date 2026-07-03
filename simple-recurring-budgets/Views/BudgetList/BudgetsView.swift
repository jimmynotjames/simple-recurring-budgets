import SwiftData
import SwiftUI

// MARK: - BudgetsView

struct BudgetsView: View {
  @Query(sort: \Budget.sortOrder) private var budgets: [Budget]
  @Environment(Router.self) private var router
  @Environment(\.modelContext) private var context
  @Environment(\.analytics) private var analytics
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  /// Standard save-error alert state for the reorder save (`budgets-screen`
  /// delta spec scenario "Failed reorder surfaces the save-error alert").
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
        // iOS 26 draws bar buttons monochrome by default and ignores the
        // asset-catalog global accent; explicit tint restores the brand accent
        // (WCAG AA per #218's darkened AccentColor). Same on all bar buttons.
        .tint(.accentColor)
        .accessibilityHint(String(
          localized: "toolbar.settings.accessibilityHint",
          defaultValue: "Opens app settings",
          comment: "VoiceOver hint for the Settings toolbar button"
        ))
        // Locale-invariant test handle (= localization key) so UI tests navigate in any language.
        // Sole consumer: LocalizationScreenshotCapture (scripts/translation-accessibility-size-check/).
        // Don't remove/rename without updating that capture, or its navigation breaks silently.
        .accessibilityIdentifier("toolbar.settings.label")
        // Only show the Edit button when there are rows to reorder.
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
            // Hide the text label at accessibility sizes: the HStack clips inside
            // the fixed-height toolbar at Accessibility Extra Large and above.
            // The explicit .accessibilityLabel below keeps VoiceOver working.
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
        // Locale-invariant test handle; sole consumer is LocalizationScreenshotCapture
        // (scripts/translation-accessibility-size-check/) — see toolbar.settings.label above.
        .accessibilityIdentifier("toolbar.addBudget.accessibilityLabel")
      }
    }
  }

  // MARK: - Private views

  private var emptyStateView: some View {
    // Custom empty state rather than ContentUnavailableView: the system component
    // imposes an undocumented line limit on its description view that causes the
    // long description string to clip on some iOS versions. Custom layout gives
    // full control over text wrapping.
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

  /// Reorders budgets after a user drag-to-reorder gesture: applies the
  /// `BudgetReorderService` rewrite, then batches all writes into a single save.
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

  /// View-layer inactive-presentation reason (`nil` when the budget is active).
  /// Drives the dimmed amount / full-width secondary bar / `InactiveStatusChip`
  /// treatment uniformly across preStart, paused, and postEnd.
  private var inactiveReason: BudgetInactiveReason? {
    guard let lifecycle else { return nil }
    return BudgetInactiveReason.from(lifecycle: lifecycle, budget: budget)
  }

  // Scale spacing and padding with the user's preferred text size,
  // except for add-expense button, which is fixed.
  @ScaledMetric(relativeTo: .headline) private var rowSpacing: CGFloat = 10
  @ScaledMetric(relativeTo: .caption) private var chipTopSpacing: CGFloat = 16
  @ScaledMetric(relativeTo: .body) private var rowVerticalPadding: CGFloat = 8

  private var isSpecificDates: Bool {
    budget.periodEnum == .specificDates
  }

  private var remaining: Decimal {
    lifecycle?.remaining ?? 0
  }

  /// The budget name, optionally prefixed by the budget's `icon` emoji. The icon is
  /// a separate leading view (not a string prefix) so it mirrors with layout
  /// direction — in RTL it sits on the right, the leading edge. The trailing space
  /// baked into the icon text reproduces a single text-space gap, so `spacing` is 0.
  /// The emoji is decorative — VoiceOver reads the explicit `.accessibilityLabel`
  /// below, which omits it.
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
      // Outer VStack groups the tappable row content with the carry-over chip.
      // The chip lives outside the Button so VoiceOver treats it as a separate
      // static-text element rather than a non-activatable nested element.
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

        // Chip row lives outside the Button so VoiceOver reads each chip as
        // its own static-text element rather than swallowing them into the
        // button's label.
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
      // Locale-invariant test handle; sole consumer is LocalizationScreenshotCapture
      // (scripts/translation-accessibility-size-check/) — see toolbar.settings.label above.
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
    // Recompute when the budget OR any of its children change — including a CloudKit
    // remote merge that brings in expenses without re-bumping `budget.lastModified`
    // (issue #127). See `Budget.recomputeToken`.
    .onChange(of: budget.recomputeToken) {
      refreshLifecycle()
    }
    // Recompute when a period boundary passes while the app stays foregrounded
    // (issue #70) — scenePhase/recomputeToken don't fire at midnight.
    .onCalendarDayChange {
      refreshLifecycle()
    }
    // Recompute when Week Starts On changes (confirmed in Settings or synced from
    // another device via iCloud KVS) — weekly budgets re-grid immediately (#240).
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

  // Seeded fixtures carry icons on a few budgets (see DebugData), so these show the
  // emoji prefix on some rows and name-only on others.
  #Preview("Light Mode") { BudgetsPreview() }
  #Preview("Dark Mode") { BudgetsPreview().preferredColorScheme(.dark) }
  // Just below reformatting threshold.
  #Preview("xxLarge") { BudgetsPreview().dynamicTypeSize(.xxLarge) }
  // Just at reformatting threshold. (Changes from horizontal stack to vertical).
  #Preview("xxxLarge") { BudgetsPreview().dynamicTypeSize(.xxxLarge) }
  #Preview("Empty state") { BudgetsPreview(empty: true) }
#endif
