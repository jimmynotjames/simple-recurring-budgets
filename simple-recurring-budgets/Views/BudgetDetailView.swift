import SwiftData
import SwiftUI

// MARK: - BudgetDetailView

struct BudgetDetailView: View {
  let budget: Budget

  @Environment(\.modelContext) var context
  @Environment(AppSettings.self) var settings
  @Environment(Router.self) private var router
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  @State var lifecycle: BudgetLifecycleResult?
  @State var expenseToDelete: ExpenseItem?
  @State var showDeleteConfirm = false
  @State private var showResetCarryOverConfirm = false
  @State private var showResetBudgetConfirm = false

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
    lifecycle?.carryOverAmount ?? budget.carryOverAmount
  }

  private var remainingFraction: Double {
    guard budget.allocation > 0 else { return 0 }
    let ratio = remaining / budget.allocation
    return max(0, min(1, (ratio as NSDecimalNumber).doubleValue))
  }

  private var isOverBudget: Bool {
    remaining < 0
  }

  private var amountLayout: AnyLayout {
    dynamicTypeSize >= .xxxLarge
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: amountSpacing))
      : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: amountSpacing))
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
        Button {
          router.sheet = .addExpense(budget)
        } label: {
          let title = String(
            localized: "budgetDetail.action.addExpense",
            defaultValue: "Add Expense",
            comment: "Label on the primary action button that opens the add expense form"
          )
          Label(title, systemImage: "plus")
            .font(.headline)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
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
          Divider()
          Button(
            String(
              localized: "budgetDetail.menu.resetBudget",
              defaultValue: "Reset Budget…",
              comment: "Menu item that opens the reset budget confirmation dialog"
            ),
            systemImage: "trash",
            role: .destructive
          ) {
            showResetBudgetConfirm = true
          }
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
          Button("Cancel", role: .cancel) {}
        } message: {
          Text(
            "budgetDetail.resetBudget.dialog.message",
            comment: "Body of the reset-budget confirmation dialog."
          )
        }
      }
    }
    .confirmationDialog(
      String(
        localized: "budgetDetail.deleteExpense.dialog.title",
        defaultValue: "Delete this expense?",
        comment: "Title of the confirmation dialog when the user swipes to delete an expense"
      ),
      isPresented: $showDeleteConfirm,
      titleVisibility: .visible
    ) {
      Button(
        String(
          localized: "budgetDetail.deleteExpense.dialog.confirm",
          defaultValue: "Delete",
          comment: "Destructive confirm button in the delete expense confirmation dialog"
        ),
        role: .destructive
      ) {
        if let e = expenseToDelete { deleteExpense(e) }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      if let name = expenseToDelete?.name {
        Text(String(
          localized: "budgetDetail.deleteExpense.dialog.message",
          defaultValue: "\(name) will be permanently removed.",
          comment: "Body of the delete expense dialog when the expense has a name; argument is the expense name"
        ))
      } else {
        Text(String(
          localized: "budgetDetail.deleteExpense.dialog.message.unnamed",
          defaultValue: "This expense will be permanently removed.",
          comment: "Body of the delete expense dialog when the expense has no name"
        ))
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
      Button("Cancel", role: .cancel) {}
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
    .onChange(of: budget.expenseItems.count) {
      refreshLifecycle()
    }
  }

  // MARK: - Header row

  private var headerRow: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: rowSpacing) {
        amountLayout {
          Text(remaining.formatted(currencyCode: budget.currencyCode, display: settings.currencyDisplay))
            .font(.largeTitle)
            .monospacedDigit()
            .foregroundStyle(isOverBudget ? Color.moneyDeficit : .primary)
            .lineLimit(1)

          Text(period.listLabel)
            .font(.callout)
            .foregroundStyle(.secondary)
        }

        RemainingBar(remainingFraction: remainingFraction, isOverBudget: isOverBudget)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityElement(children: .combine)
      .accessibilityLabel(headerA11yLabel)

      if budget.isCarryOverEnabled {
        HStack(alignment: .center, spacing: 8) {
          CarryOverChip(
            amount: carryOverAmount,
            currencyCode: budget.currencyCode,
            display: settings.currencyDisplay
          )
          .accessibilityAddTraits(.isStaticText)
          Button(String(
            localized: "budgetDetail.resetCarryOver.button",
            defaultValue: "Reset",
            comment: "Label for the button that resets the carry-over balance to zero"
          )) { showResetCarryOverConfirm = true }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel(String(
              localized: "budgetDetail.resetCarryOver.button.accessibilityLabel",
              defaultValue: "Reset carry-over to zero",
              comment: "VoiceOver label for the reset carry-over button"
            ))
        }
        .padding(.top, chipTopSpacing)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, rowVerticalPadding)
  }

  // MARK: - Actions

  func refreshLifecycle() {
    lifecycle = BudgetLifecycleService.refreshAndSave(
      budget, settings: settings, context: context
    )
  }

  private func resetCarryOver() {
    budget.carryOverAmount = 0
    budget.carryOverLastResetDate = Date()
    budget.lastModified = Date()
    try? context.save()
    refreshLifecycle()
  }

  private func resetBudget() {
    withAnimation {
      for expense in Array(budget.expenseItems) {
        context.delete(expense)
      }
      budget.carryOverAmount = 0
      budget.carryOverLastResetDate = Date()
      budget.lastModified = Date()
      try? context.save()
    }
    refreshLifecycle()
  }

  // MARK: - Accessibility

  private var headerA11yLabel: String {
    isOverBudget
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
#endif
