import OSLog
import SwiftData
import SwiftUI

// MARK: - BudgetDetailView

struct BudgetDetailView: View {
  let budget: Budget

  @Environment(\.modelContext) var context
  @Environment(AppSettings.self) var settings
  @Environment(Router.self) var router
  @Environment(\.analytics) var analytics
  @Environment(\.scenePhase) private var scenePhase

  @State var lifecycle: BudgetLifecycleResult?
  @State private var showResetCarryOverConfirm = false
  @State private var showResetBudgetConfirm = false

  private var isPaused: Bool {
    lifecycle?.lifecycleState == .paused
  }

  private var isPostEnd: Bool {
    lifecycle?.lifecycleState == .postEnd
  }

  private var isSpecificDates: Bool {
    BudgetPeriod(rawValue: budget.period) == .specificDates
  }

  private var showPauseResumeItem: Bool {
    !isSpecificDates && !isPostEnd
  }

  @ScaledMetric(relativeTo: .headline) private var rowSpacing: CGFloat = 10
  @ScaledMetric(relativeTo: .callout) private var amountSpacing: CGFloat = 6
  @ScaledMetric(relativeTo: .caption) private var chipTopSpacing: CGFloat = 16
  @ScaledMetric(relativeTo: .body) private var rowVerticalPadding: CGFloat = 8

  var period: BudgetPeriod {
    BudgetPeriod(rawValue: budget.period) ?? .daily
  }

  private var remaining: Decimal {
    lifecycle?.remaining ?? 0
  }

  private var carryOverAmount: Decimal {
    lifecycle?.carryOverAmount ?? 0
  }

  private var remainingFraction: Double {
    let allocation = budget.currentAllocation
    guard allocation > 0 else { return 0 }
    let ratio = remaining / allocation
    return max(0, min(1, (ratio as NSDecimalNumber).doubleValue))
  }

  private var isOverBudget: Bool {
    remaining < 0
  }

  var body: some View {
    List {
      // ── Status header ─────────────────────────────────────────
      Section {
        headerRow
          .listRowBackground(Color("CellBackground"))
          .listRowSeparator(.hidden)
      }

      // ── Primary action ────────────────────────────────────────
      Section {
        VStack(spacing: 8) {
          if isPaused {
            Button {
              resumeBudgetTapped()
            } label: {
              HStack(spacing: 8) {
                Image(systemName: "play.circle")
                Text(String(
                  localized: "budgetDetail.action.resume",
                  defaultValue: "Resume Budget",
                  comment: "Label on the primary action button when the budget is paused"
                ))
              }
              .font(.headline)
              .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityLabel(String(
              localized: "budgetDetail.action.resume.accessibilityLabel",
              defaultValue: "Resume \(budget.name)",
              comment: "VoiceOver label for the resume budget button; argument is the budget name"
            ))
            .accessibilityHint(String(
              localized: "budgetDetail.action.resume.accessibilityHint",
              defaultValue: "Resumes the budget so you can log expenses again",
              comment: "VoiceOver hint for the resume budget button"
            ))
            if let pausedSince = lifecycle?.pausedSince {
              Text(String(
                localized: "budgetDetail.action.resume.caption.format",
                defaultValue: "Paused since \(pausedSince.formatted(date: .abbreviated, time: .omitted)). Resume to log new expenses.",
                comment: "Caption below the Resume Budget button; argument is the abbreviated pause date"
              ))
              .font(.caption)
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity, alignment: .center)
            }
          } else {
            Button {
              router.sheet = .addExpense(budget)
            } label: {
              HStack(spacing: 8) {
                Image(systemName: "plus")
                Text(String(
                  localized: "budgetDetail.action.addExpense",
                  defaultValue: "Add Expense",
                  comment: "Label on the primary action button that opens the add expense form"
                ))
              }
              .font(.headline)
              .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityLabel(String(
              localized: "budgetDetail.action.addExpense.accessibilityLabel",
              defaultValue: "Add expense to \(budget.name)",
              comment: "VoiceOver label for the add expense button; argument is the budget name"
            ))
            .accessibilityHint(String(
              localized: "budgetDetail.action.addExpense.accessibilityHint",
              defaultValue: "Opens the add expense form",
              comment: "VoiceOver hint for the add expense button"
            ))
          }
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
      }

      // ── Expense list ──────────────────────────────────────────
      expenseSection
    }
    .listStyle(.insetGrouped)
    .scrollContentBackground(.hidden)
    .navigationTitle(budget.name)
    .appBackground()
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          Button(
            String(
              localized: "budgetDetail.menu.editBudget",
              defaultValue: "Edit Budget",
              comment: "Menu item that opens the edit budget form"
            ),
            systemImage: "pencil"
          ) {
            router.sheet = .editBudget(budget)
          }
          if showPauseResumeItem {
            if isPaused {
              Button(
                String(
                  localized: "budgetDetail.menu.resumeBudget",
                  defaultValue: "Resume Budget",
                  comment: "Menu item to resume a paused budget"
                ),
                systemImage: "play.circle"
              ) {
                resumeBudgetTapped()
              }
            } else {
              Button(
                String(
                  localized: "budgetDetail.menu.pauseBudget",
                  defaultValue: "Pause Budget",
                  comment: "Menu item to pause an active budget"
                ),
                systemImage: "pause.circle"
              ) {
                pauseBudgetTapped()
              }
            }
          }
          Divider()
          if budget.isCarryOverEnabled, !isSpecificDates {
            Button(
              String(
                localized: "budgetDetail.menu.resetCarryOver",
                defaultValue: "Reset Carry-Over…",
                comment: "Menu item that opens the reset carry-over confirmation alert; mirrors the 'Reset Budget…' menu item naming convention"
              ),
              systemImage: "arrow.counterclockwise.circle",
              role: .destructive
            ) {
              showResetCarryOverConfirm = true
            }
            .accessibilityHint(String(
              localized: "budgetDetail.menu.resetCarryOver.accessibilityHint",
              defaultValue: "Clears the carry-over balance to zero. Expenses are not affected.",
              comment: "VoiceOver hint for the Reset Carry-Over menu item, communicating the destructive (but non-cascading) consequence"
            ))
          }
          Button(
            String(
              localized: "budgetDetail.menu.resetBudget",
              defaultValue: "Reset Budget…",
              comment: "Menu item that opens the reset budget confirmation dialog"
            ),
            systemImage: "arrow.counterclockwise",
            role: .destructive
          ) {
            showResetBudgetConfirm = true
          }
          .accessibilityHint(String(
            localized: "budgetDetail.menu.resetBudget.accessibilityHint",
            defaultValue: "Permanently deletes every expense for this budget, resets carry-over to zero, and resumes the budget if it is paused.",
            comment: "VoiceOver hint for the destructive Reset Budget menu item, communicating the irreversible consequence"
          ))
        } label: {
          Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel(String(
          localized: "budgetDetail.menu.accessibilityLabel",
          defaultValue: "Budget options",
          comment: "VoiceOver label for the budget options menu button"
        ))
        .confirmationDialog(
          String(
            localized: "budgetDetail.resetBudget.dialog.title",
            defaultValue: "Reset Budget?",
            comment: "Title of the confirmation dialog when the user chooses to reset a budget"
          ),
          isPresented: $showResetBudgetConfirm,
          titleVisibility: .visible
        ) {
          Button(
            String(
              localized: "budgetDetail.resetBudget.dialog.confirm",
              defaultValue: "Reset Budget",
              comment: "Destructive confirm button in the reset budget confirmation dialog"
            ),
            role: .destructive
          ) { resetBudget() }
        } message: {
          Text(String(
            localized: "budgetDetail.resetBudget.dialog.message",
            defaultValue: "All expenses will be permanently deleted, carry-over will reset to zero, and if paused, the budget will resume.",
            comment: "Body of the reset-budget confirmation dialog."
          ))
        }
      }
    }
    .alert(
      String(
        localized: "budgetDetail.resetCarryOver.alert.title",
        defaultValue: "Reset carry-over?",
        comment: "Title of the alert when the user resets the carry-over balance to zero"
      ),
      isPresented: $showResetCarryOverConfirm
    ) {
      Button(
        String(
          localized: "budgetDetail.resetCarryOver.alert.confirm",
          defaultValue: "Reset to Zero",
          comment: "Destructive confirm button in the reset carry-over alert"
        ),
        role: .destructive
      ) { resetCarryOver() }
    } message: {
      Text(String(
        localized: "budgetDetail.resetCarryOver.alert.message",
        defaultValue: "The carry-over balance will be cleared and start fresh from zero.",
        comment: "Body of the reset carry-over alert"
      ))
    }
    .task(id: budget.persistentModelID) {
      refreshLifecycle()
    }
    .onChange(of: scenePhase) { _, newPhase in
      guard newPhase == .active else { return }
      refreshLifecycle()
    }
    .onChange(of: budget.lastModified) {
      refreshLifecycle()
    }
  }

  // MARK: - Header row

  private var headerRow: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: rowSpacing) {
        ViewThatFits(in: .horizontal) {
          HStack(alignment: .firstTextBaseline, spacing: amountSpacing) {
            Text(remaining.formatted(currencyCode: budget.currencyCode, display: settings.currencyDisplay))
              .font(.largeTitle)
              .monospacedDigit()
              .foregroundStyle(dimmedStyle(isOverBudget ? Color.moneyDeficit : .primary, when: isPaused))
              .lineLimit(1)
            Text(budget.periodDisplayLabel)
              .font(.callout)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
          VStack(alignment: .leading, spacing: amountSpacing) {
            Text(remaining.formatted(currencyCode: budget.currencyCode, display: settings.currencyDisplay))
              .font(.largeTitle)
              .monospacedDigit()
              .foregroundStyle(dimmedStyle(isOverBudget ? Color.moneyDeficit : .primary, when: isPaused))
              .lineLimit(1)
            Text(budget.periodDisplayLabel)
              .font(.callout)
              .foregroundStyle(.secondary)
          }
        }

        RemainingBar(remainingFraction: remainingFraction, isOverBudget: isOverBudget, dimmed: isPaused)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityElement(children: .combine)
      .accessibilityLabel(headerA11yLabel)
      .accessibilityAddTraits(.isHeader)

      StatusChipRow(
        isPaused: isPaused,
        pausedSince: lifecycle?.pausedSince,
        isCarryOverEnabled: budget.isCarryOverEnabled && !isSpecificDates,
        carryOverAmount: carryOverAmount,
        currencyCode: budget.currencyCode,
        currencyDisplay: settings.currencyDisplay,
        topSpacing: chipTopSpacing
      )
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, rowVerticalPadding)
  }

  // MARK: - Actions

  func refreshLifecycle() {
    lifecycle = BudgetLifecycleService.result(for: budget)
  }

  // pauseBudgetTapped / resumeBudgetTapped live in BudgetDetailView+PauseResume.swift

  private func resetCarryOver() {
    Logger.ui.debug(
      "ui.action: resetCarryOver budget=\(String(describing: budget.persistentModelID), privacy: .private)"
    )
    let period = BudgetPeriod(rawValue: budget.period) ?? .daily
    BudgetLifecycleService.resetCarryOver(budget, context: context)
    // ⚠️ Boundary-adjacent (sibling pattern): Logger.ui.debug above (F-8.01) and
    // analytics.track below (F-8.02) are independent siblings. See design.md D6.
    analytics.track(
      AnalyticsEvent.carryOverReset,
      properties: [
        AnalyticsProperty.period: period.analyticsValue,
        AnalyticsProperty.carryOverEnabled: budget.isCarryOverEnabled,
        AnalyticsProperty.currencyCode: budget.currencyCode,
        AnalyticsProperty.budgetName: budget.name,
        AnalyticsProperty.budgetAllocationAmount: (budget.currentAllocation as NSDecimalNumber).doubleValue,
      ]
    )
    refreshLifecycle()
  }

  private func resetBudget() {
    Logger.ui.debug(
      "ui.action: resetBudget budget=\(String(describing: budget.persistentModelID), privacy: .private)"
    )
    let period = BudgetPeriod(rawValue: budget.period) ?? .daily
    withAnimation {
      BudgetLifecycleService.resetBudget(budget, context: context)
    }
    // ⚠️ Boundary-adjacent (sibling pattern): Logger.ui.debug above (F-8.01) and
    // analytics.track below (F-8.02) are independent siblings. See design.md D6.
    analytics.track(
      AnalyticsEvent.budgetReset,
      properties: [
        AnalyticsProperty.period: period.analyticsValue,
        AnalyticsProperty.carryOverEnabled: budget.isCarryOverEnabled,
        AnalyticsProperty.currencyCode: budget.currencyCode,
        AnalyticsProperty.budgetName: budget.name,
        AnalyticsProperty.budgetAllocationAmount: (budget.currentAllocation as NSDecimalNumber).doubleValue,
      ]
    )
    refreshLifecycle()
  }

  // MARK: - Accessibility

  /// Builds the VoiceOver label for the header.
  ///
  /// The paused state is announced separately by `PausedChip`'s own VO element,
  /// so this label only carries the data (remaining + period, or over-budget).
  private var headerA11yLabel: String {
    if isSpecificDates {
      return isOverBudget
        ? String(
          localized: "budgetDetail.header.accessibilityLabel.overBudget.specificDates",
          defaultValue: "\((-remaining).formatted(currencyCode: budget.currencyCode, display: settings.currencyDisplay)) over budget \(budget.periodInlineLabel)",
          comment: "VoiceOver label for the Specific Dates budget detail header when over budget; first argument is the formatted overage amount, second is the inline period descriptor (e.g. \"in this window\")"
        )
        : String(
          localized: "budgetDetail.header.accessibilityLabel.specificDates",
          defaultValue: "\(remaining.formatted(currencyCode: budget.currencyCode, display: settings.currencyDisplay)) remaining \(budget.periodInlineLabel)",
          comment: "VoiceOver label for the Specific Dates budget detail header; first argument is the remaining amount, second is the inline period descriptor (e.g. \"in this window\")"
        )
    }
    return isOverBudget
      ? String(
        localized: "budgetDetail.header.accessibilityLabel.overBudget",
        defaultValue: "\((-remaining).formatted(currencyCode: budget.currencyCode, display: settings.currencyDisplay)) over budget this \(period.inlineLabel) period",
        comment: "VoiceOver label for the budget header when over budget; first argument is the formatted overage amount, second is the period name"
      )
      : String(
        localized: "budgetDetail.header.accessibilityLabel",
        defaultValue: "\(remaining.formatted(currencyCode: budget.currencyCode, display: settings.currencyDisplay)) remaining this \(period.inlineLabel) period",
        comment: "VoiceOver label for the budget header; first argument is the formatted remaining amount, second is the period name"
      )
  }
}

// MARK: - Preview

#if DEBUG
  private struct BudgetDetailPreview: View {
    let budget: Budget
    let container: ModelContainer

    init(budget: Budget) {
      self.budget = budget
      let container = InMemoryModelContainer.makeEmpty()
      DebugData.insertDetail(budget, into: container.mainContext)
      self.container = container
    }

    var body: some View {
      NavigationStack {
        BudgetDetailView(budget: budget)
      }
      .modelContainer(container)
      .environment(Router())
      .environment(AppSettings())
    }
  }

  // Current-period expenses only (daily budget, all from today).
  #Preview("Current Period Only") {
    BudgetDetailPreview(budget: DebugData.detailDailyCurrentOnly())
  }

  // Both current and past period expenses (monthly, long — exceeds screen height).
  #Preview("Current & Past Months") {
    BudgetDetailPreview(budget: DebugData.detailMonthlyCurrentAndPast())
  }

  // No current-period expenses; all expenses are from past periods (weekly budget).
  #Preview("Past Periods Only") {
    BudgetDetailPreview(budget: DebugData.detailWeeklyPastOnly())
  }

  // Empty — no expenses at all.
  #Preview("Empty") {
    BudgetDetailPreview(budget: DebugData.detailWeeklyEmpty())
  }

  // Carry-over disabled.
  #Preview("Carry-Over Disabled") {
    BudgetDetailPreview(budget: DebugData.detailMonthlyCarryOverDisabled())
  }

  // Dark mode, over budget.
  #Preview("Dark · Over Budget") {
    BudgetDetailPreview(budget: DebugData.detailWeeklyOverBudget())
      .preferredColorScheme(.dark)
  }

  // Paused budget — primary slot shows Resume, header greyed.
  #Preview("Paused") {
    BudgetDetailPreview(budget: DebugData.detailDailyPaused())
  }

  // Specific Dates — date range in header, no carry-over chip.
  #Preview("Specific Dates · Light") {
    BudgetDetailPreview(budget: DebugData.detailSpecificDates())
  }

  #Preview("Specific Dates · Dark") {
    BudgetDetailPreview(budget: DebugData.detailSpecificDates())
      .preferredColorScheme(.dark)
  }
#endif
