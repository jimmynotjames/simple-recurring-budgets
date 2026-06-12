import OSLog
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
        .foregroundStyle(.readableSecondary)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 32)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
      }
    } else {
      let future = futurePeriodExpenses
      let past = pastPeriodExpenses
      let current = currentPeriodExpenses
      // Future-dated expenses live above the current section (the list is
      // reverse-chronological) in a single "Upcoming" bucket for all future
      // periods — they don't count toward Remaining until their date arrives,
      // so mixing them into the current section made its total disagree with
      // the headline (audit L2).
      if !future.isEmpty {
        Section(futureSectionTitle) {
          ForEach(future) { expense in expenseRow(expense) }
        }
      }
      if current.isEmpty {
        Section(currentSectionTitle) {
          Text(currentPeriodEmptyText)
            .font(.subheadline)
            .foregroundStyle(.readableSecondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 12)
            .listRowBackground(Color("CellBackground"))
            .listRowSeparator(.hidden)
        }
      } else {
        let totalString = currentPeriodTotal.formatted(currencyCode: budget.currencyCode, display: settings.currencyDisplay)
        Section {
          ForEach(current) { expense in expenseRow(expense) }
        } header: {
          HStack {
            Text(currentSectionTitle)
            Spacer()
            Text(totalString)
              .monospacedDigit()
              .textCase(nil)
          }
          // Coalesce the title + total into a single VoiceOver element so
          // it reads "Current Day, total $20.00" rather than as two
          // separate static-text elements.
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(String(
            localized: "budgetDetail.section.current.accessibilityLabel",
            defaultValue: "\(currentSectionTitle), total \(totalString)",
            comment:
            "VoiceOver label for the current-period section header on the Budget detail screen. First argument is the section title (e.g. \"Current Day\"); second is the formatted running total in the budget's currency."
          ))
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
    Button {
      router.path.append(AppRoute.expenseDetail(expense.id))
    } label: {
      ExpenseRowView(expense: expense, currencyCode: budget.currencyCode)
    }
    .buttonStyle(.plain)
    .listRowBackground(Color("CellBackground"))
    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
      Button(role: .destructive) {
        deleteExpense(expense)
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
    // SwiftUI does not auto-expose `swipeActions` to VoiceOver. Without an
    // explicit `accessibilityAction`, VO users cannot delete expenses.
    .accessibilityAction(named: Text(String(
      localized: "budgetDetail.expenseRow.accessibilityAction.delete",
      defaultValue: "Delete",
      comment: "VoiceOver custom action name on an expense row that mirrors the trailing-edge swipe-to-delete gesture, so VoiceOver users can delete via the rotor Actions"
    ))) {
      deleteExpense(expense)
    }
  }

  func deleteExpense(_ expense: ExpenseItem) {
    Logger.ui.debug(
      "ui.action: deleteExpense expense=\(String(describing: expense.persistentModelID), privacy: .private)"
    )
    let period = budget.periodEnum
    let isAddFunds = expense.isAddFunds
    do {
      try withAnimation {
        budget.lastModified = Date()
        context.delete(expense)
        try context.saveChanges(operation: .expenseDelete, analytics: analytics)
      }
    } catch let error as PersistenceError {
      // Failed save: surface the standard save-error alert and skip the
      // analytics emission (`budget-detail-screen` delta spec scenario
      // "Failed swipe-delete surfaces the save-error alert").
      saveError.setForFailure(error, retry: { [self] in deleteExpense(expense) })
      return
    } catch {
      return
    }
    saveError.clear()
    // ⚠️ Boundary-adjacent (sibling pattern): Logger.ui.debug above (F-8.01) and
    // analytics.track below (F-8.02) are independent siblings. See design.md D6.
    // expense_deleted fires only on a successful save.
    analytics.track(
      AnalyticsEvent.expenseDeleted,
      properties: [
        AnalyticsProperty.period: period.analyticsValue,
        AnalyticsProperty.isAddFunds: isAddFunds,
        AnalyticsProperty.fromScreen: "budget_detail",
      ]
    )
    refreshLifecycle()
  }

  var currentPeriodTotal: Decimal {
    currentPeriodExpenses.reduce(0) { $0 + $1.amount }
  }

  private var partitionedExpenses: PartitionedExpenses {
    budget.expenseItems.partitioned(
      byPeriodStart: lifecycle?.periodStart,
      periodEnd: lifecycle?.periodEnd
    )
  }

  var futurePeriodExpenses: [ExpenseItem] {
    partitionedExpenses.future
  }

  var currentPeriodExpenses: [ExpenseItem] {
    partitionedExpenses.current
  }

  var pastPeriodExpenses: [ExpenseItem] {
    partitionedExpenses.past
  }

  /// Single bucket for all future-dated expenses, regardless of period type —
  /// unlike `currentSectionTitle` / `pastSectionTitle` there is no per-period
  /// variant (audit L2 decision).
  var futureSectionTitle: String {
    String(
      localized: "budgetDetail.section.future",
      defaultValue: "Upcoming",
      comment: "Section header on the Budget detail screen for expenses dated after the current period ends — a single bucket for all future-dated entries, shown above the current-period section. One word — keep terse."
    )
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
    case .specificDates:
      String(
        localized: "budgetDetail.section.current.specificDates",
        defaultValue: "Current Period",
        comment: "Section header for expenses in a specific-dates budget window"
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
    case .specificDates:
      String(
        localized: "budgetDetail.section.past.specificDates",
        defaultValue: "Past Periods",
        comment: "Section header for expenses from past periods of a specific-dates budget"
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
    case .specificDates:
      String(
        localized: "budgetDetail.currentPeriod.empty.specificDates",
        defaultValue: "Nothing logged this period",
        comment: "Empty state for the current period section when the budget period is specific dates"
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
    // Extend hit-test area to full row frame; plain button style only hits rendered pixels otherwise.
    .contentShape(Rectangle())
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
        defaultValue: "Untitled",
        comment: "Placeholder name shown for an expense or add-funds entry that has no title"
      ))
      .font(.body.italic())
      .foregroundStyle(.secondary)
    }
  }

  private var a11yLabel: String {
    let amountStr = expense.displayAmount.formatted(currencyCode: currencyCode, display: settings.currencyDisplay)
    let nameStr = expense.name ?? String(
      localized: "budgetDetail.expenseRow.unnamed",
      defaultValue: "Untitled",
      comment: "Placeholder name shown for an expense or add-funds entry that has no title"
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
