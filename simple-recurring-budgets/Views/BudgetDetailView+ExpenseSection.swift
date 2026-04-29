import SwiftData
import SwiftUI

// MARK: - Expense section

extension BudgetDetailView {
  @ViewBuilder
  var expenseSection: some View {
    if budget.expenseItems.isEmpty {
      Section {
        Text(String(
          localized: "budgetDetail.empty.noExpenses",
          defaultValue: "No expenses logged yet.",
          comment: "Empty state message shown when a budget has no expenses at all"
        ))
        .font(.body)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 32)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
      }
    } else {
      let current = currentPeriodExpenses
      let past = pastPeriodExpenses
      if current.isEmpty {
        Section(currentSectionTitle) {
          Text(currentPeriodEmptyText)
            .font(.subheadline)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 12)
            .listRowBackground(Color("CellBackground"))
            .listRowSeparator(.hidden)
        }
      } else {
        Section {
          ForEach(current) { expense in expenseRow(expense) }
        } header: {
          HStack {
            Text(currentSectionTitle)
            Spacer()
            Text(currentPeriodTotal.formatted(currencyCode: budget.currencyCode, display: settings.currencyDisplay))
              .monospacedDigit()
              .textCase(nil)
          }
        }
      }
      if !past.isEmpty {
        Section(pastSectionTitle) {
          ForEach(past) { expense in expenseRow(expense) }
        }
      }
    }
  }

  func expenseRow(_ expense: ExpenseItem) -> some View {
    ExpenseRowView(expense: expense, currencyCode: budget.currencyCode)
      .listRowBackground(Color("CellBackground"))
      .swipeActions(edge: .trailing, allowsFullSwipe: false) {
        Button(role: .destructive) {
          expenseToDelete = expense
          showDeleteConfirm = true
        } label: {
          Label(
            String(
              localized: "budgetDetail.deleteExpense.swipeAction",
              defaultValue: "Delete",
              comment: "Label on the swipe-to-delete action for an expense row"
            ),
            systemImage: "trash"
          )
        }
      }
  }

  func deleteExpense(_ expense: ExpenseItem) {
    withAnimation {
      context.delete(expense)
      try? context.save()
    }
    refreshLifecycle()
  }

  var currentPeriodTotal: Decimal {
    currentPeriodExpenses.reduce(0) { $0 + $1.amount }
  }

  private var partitionedExpenses: (current: [ExpenseItem], past: [ExpenseItem]) {
    budget.expenseItems.partitioned(byPeriodStart: lifecycle?.periodStart)
  }

  var currentPeriodExpenses: [ExpenseItem] {
    partitionedExpenses.current
  }

  var pastPeriodExpenses: [ExpenseItem] {
    partitionedExpenses.past
  }

  var currentSectionTitle: String {
    switch period {
    case .daily:
      String(
        localized: "budgetDetail.section.current.daily",
        defaultValue: "Current Day",
        comment: "Section header for expenses in the current day"
      )
    case .weekly:
      String(
        localized: "budgetDetail.section.current.weekly",
        defaultValue: "Current Week",
        comment: "Section header for expenses in the current week"
      )
    case .biweekly:
      String(
        localized: "budgetDetail.section.current.biweekly",
        defaultValue: "Current Period",
        comment: "Section header for expenses in the current biweekly period"
      )
    case .monthly:
      String(
        localized: "budgetDetail.section.current.monthly",
        defaultValue: "Current Month",
        comment: "Section header for expenses in the current month"
      )
    }
  }

  var pastSectionTitle: String {
    switch period {
    case .daily:
      String(
        localized: "budgetDetail.section.past.daily",
        defaultValue: "Past Days",
        comment: "Section header for expenses from previous days"
      )
    case .weekly:
      String(
        localized: "budgetDetail.section.past.weekly",
        defaultValue: "Past Weeks",
        comment: "Section header for expenses from previous weeks"
      )
    case .biweekly:
      String(
        localized: "budgetDetail.section.past.biweekly",
        defaultValue: "Past Periods",
        comment: "Section header for expenses from previous biweekly periods"
      )
    case .monthly:
      String(
        localized: "budgetDetail.section.past.monthly",
        defaultValue: "Past Months",
        comment: "Section header for expenses from previous months"
      )
    }
  }

  var currentPeriodEmptyText: String {
    switch period {
    case .daily:
      String(
        localized: "budgetDetail.currentPeriod.empty.daily",
        defaultValue: "Nothing logged today",
        comment: "Empty state for the current period section when the budget period is daily"
      )
    case .weekly:
      String(
        localized: "budgetDetail.currentPeriod.empty.weekly",
        defaultValue: "Nothing logged this week",
        comment: "Empty state for the current period section when the budget period is weekly"
      )
    case .biweekly:
      String(
        localized: "budgetDetail.currentPeriod.empty.biweekly",
        defaultValue: "Nothing logged this period",
        comment: "Empty state for the current period section when the budget period is biweekly"
      )
    case .monthly:
      String(
        localized: "budgetDetail.currentPeriod.empty.monthly",
        defaultValue: "Nothing logged this month",
        comment: "Empty state for the current period section when the budget period is monthly"
      )
    }
  }
}

// MARK: - ExpenseRowView

private struct ExpenseRowView: View {
  let expense: ExpenseItem
  let currencyCode: String

  @Environment(AppSettings.self) private var settings
  @ScaledMetric(relativeTo: .body) private var rowVerticalPadding: CGFloat = 2

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        nameText
        Text(expense.date.formattedForExpenseList())
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      Text(expense.displayAmount.formatted(currencyCode: currencyCode, display: settings.currencyDisplay))
        .font(.body)
        .monospacedDigit()
        .foregroundStyle(expense.isAddFunds ? Color.moneySurplus : .primary)
    }
    .padding(.vertical, rowVerticalPadding)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(a11yLabel)
  }

  @ViewBuilder
  private var nameText: some View {
    if let name = expense.name {
      Text(name)
        .font(.body)
        .lineLimit(3)
    } else {
      Text(String(
        localized: "budgetDetail.expenseRow.unnamed",
        defaultValue: "Untitled expense",
        comment: "Placeholder name shown for an expense that has no title"
      ))
      .font(.body.italic())
      .foregroundStyle(.secondary)
    }
  }

  private var a11yLabel: String {
    let amountStr = expense.displayAmount.formatted(currencyCode: currencyCode, display: settings.currencyDisplay)
    let nameStr = expense.name ?? String(
      localized: "budgetDetail.expenseRow.unnamed",
      defaultValue: "Untitled expense",
      comment: "Placeholder name shown for an expense that has no title"
    )
    let dateStr = expense.date.formattedForExpenseList()
    return expense.isAddFunds
      ? String(
        localized: "budgetDetail.expenseRow.accessibilityLabel.addFunds",
        defaultValue: "\(amountStr) added, \(nameStr), \(dateStr)",
        comment: "VoiceOver label for an add-funds expense row; arguments are the formatted amount, name, and formatted date"
      )
      : String(
        localized: "budgetDetail.expenseRow.accessibilityLabel",
        defaultValue: "\(amountStr), \(nameStr), \(dateStr)",
        comment: "VoiceOver label for an expense row; arguments are the formatted amount, name, and formatted date"
      )
  }
}
