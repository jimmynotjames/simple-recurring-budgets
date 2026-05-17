import SwiftData
import SwiftUI

// MARK: - ViewModel

@Observable
@MainActor
final class AddEditExpenseViewModel {
  private enum Mode {
    case add(Budget)
    case edit(ExpenseItem)
  }

  var amount: Decimal?
  var name: String
  var date: Date
  let currencyCode: String

  private let mode: Mode

  /// Cached at init: the lifecycle snapshot for the bound budget at sheet-open time.
  /// Avoids re-computing on every SwiftUI body evaluation. `nil` when no budget is
  /// reachable (orphan edit case).
  private let cachedBudgetSnapshot: BudgetSnapshot?

  /// Latest most-recent `.pause` event for the bound budget; used to seed `date`
  /// at sheet-open time and as the safe upper bound for the picker when paused.
  private let cachedPauseEffectiveDate: Date?

  /// Cached at init: the abbreviated rendering of `cachedPauseEffectiveDate`.
  /// Used in the proactive paused caption; cached so we don't re-format on every body pass.
  private let cachedPausedSinceFormatted: String?

  var isEditing: Bool {
    if case .edit = mode { return true }
    return false
  }

  /// The budget driving this expense entry. Used for date-bounds validation.
  private var budget: Budget? {
    switch mode {
    case let .add(budget): budget
    case let .edit(expense): expense.budget
    }
  }

  /// Returns `true` when the selected `date` lies inside one of the budget's active-period
  /// intervals (or when the bound budget is not paused). Save eligibility uses this; the
  /// proactive paused caption does not.
  private var isDateValid: Bool {
    guard let budget, cachedBudgetSnapshot?.lifecycleState == .paused else { return true }
    let snapAtDate = BudgetCalculator.snapshot(
      budget: budget, expenses: [], now: date, calendar: .autoupdatingCurrent
    )
    return snapAtDate.lifecycleState == .active
  }

  /// The single caption rendered below the When card. Returns the violation copy when the
  /// picked date sits in a paused gap, the proactive paused copy when the bound budget is
  /// paused and the date is valid, and `nil` otherwise. The view renders zero or one
  /// caption — never both stacked.
  var pausedCaption: String? {
    guard cachedBudgetSnapshot?.lifecycleState == .paused else { return nil }
    if !isDateValid {
      return String(
        localized: "addEditExpense.date.outOfRange.caption",
        defaultValue: "Pick a date within an active period of this budget.",
        comment: "Inline caption below the date picker when the selected date falls inside a paused period"
      )
    }
    guard let formatted = cachedPausedSinceFormatted else { return nil }
    return String(
      localized: "addEditExpense.paused.caption.format",
      defaultValue: "Paused since \(formatted). You can still add expenses dated before then.",
      comment: "Proactive caption shown below the When card in Add/Edit Expense when the bound budget is paused; argument is the abbreviated pausedSince date"
    )
  }

  var canSave: Bool {
    guard (amount ?? 0) > 0 else { return false }
    return isDateValid
  }

  /// The allowed range for `date` in the picker. Lower bound is the owning budget's
  /// `effectiveStartDate`. When the budget is paused, the upper bound is the most
  /// recent `.pause` event's `effectiveDate` (a moment guaranteed to lie inside an
  /// active period since the pause-action period is itself active). Save-time
  /// validation catches dates inside paused gaps for multi-cycle histories.
  var dateRange: ClosedRange<Date> {
    guard let budget else {
      return Date.distantPast ... Date.distantFuture
    }
    let lower = budget.effectiveStartDate
    if cachedBudgetSnapshot?.lifecycleState == .paused, let pauseDate = cachedPauseEffectiveDate {
      return lower ... pauseDate
    }
    return lower ... Date.distantFuture
  }

  init(adding budget: Budget) {
    amount = nil
    name = ""
    currencyCode = budget.currencyCode
    mode = .add(budget)
    let snapshot = BudgetCalculator.snapshot(
      budget: budget, expenses: [], now: Date(), calendar: .autoupdatingCurrent
    )
    cachedBudgetSnapshot = snapshot
    let pauseDate = Self.latestPauseEffectiveDate(for: budget)
    cachedPauseEffectiveDate = pauseDate
    cachedPausedSinceFormatted = pauseDate?.formatted(date: .abbreviated, time: .omitted)
    // Seed `date`: today by default; for paused budgets, fall back to the most recent
    // pause event so the initial value lies inside an active period (and the picker
    // doesn't open with an out-of-range default).
    if snapshot.lifecycleState == .paused, let pauseDate {
      date = pauseDate
    } else {
      date = max(Date(), budget.effectiveStartDate)
    }
  }

  init(editing expense: ExpenseItem) {
    amount = expense.displayAmount
    name = expense.name ?? ""
    date = expense.date
    currencyCode = expense.budget?.currencyCode ?? (Locale.current.currency?.identifier ?? "USD")
    mode = .edit(expense)
    if let budget = expense.budget {
      cachedBudgetSnapshot = BudgetCalculator.snapshot(
        budget: budget, expenses: [], now: Date(), calendar: .autoupdatingCurrent
      )
      let pauseDate = Self.latestPauseEffectiveDate(for: budget)
      cachedPauseEffectiveDate = pauseDate
      cachedPausedSinceFormatted = pauseDate?.formatted(date: .abbreviated, time: .omitted)
    } else {
      cachedBudgetSnapshot = nil
      cachedPauseEffectiveDate = nil
      cachedPausedSinceFormatted = nil
    }
  }

  /// Returns the `effectiveDate` of the most recent `.pause` `LifecycleEvent` that
  /// is not followed by a later `.resume`. Mirrors the helper in
  /// `BudgetLifecycleService.result(for:)`.
  private static func latestPauseEffectiveDate(for budget: Budget) -> Date? {
    let sorted = budget.lifecycleEvents.sorted {
      ($0.effectiveDate, $0.lastModified) < ($1.effectiveDate, $1.lastModified)
    }
    var latest: Date?
    for event in sorted {
      switch event.kind {
      case .pause: latest = event.effectiveDate
      case .resume: latest = nil
      }
    }
    return latest
  }

  /// Convenience overload for tests and call sites without an `AnalyticsClient` in scope.
  func save(context: ModelContext) {
    save(context: context, analytics: ConsoleAnalyticsClient())
  }

  func save(context: ModelContext, analytics: any AnalyticsClient) {
    // Trim whitespace; empty-after-trim collapses to nil (spec: "Form fields are Amount, Description, and When")
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedName: String? = trimmed.isEmpty ? nil : trimmed
    switch mode {
    case let .add(budget):
      // Guard per spec: "Save in Add mode inserts a new ExpenseItem attached to the in-flight Budget"
      guard canSave, let amount else { return }
      let now = Date()
      let expense = ExpenseItem(amount: amount, name: trimmedName, date: date)
      expense.budget = budget
      context.insert(expense)
      budget.lastModified = now
      try? context.save()

      // expense_logged: NO ExpenseItem field transmitted — only categorical context.
      let period = BudgetPeriod(rawValue: budget.period) ?? .daily
      let elapsed = Date().timeIntervalSince(budget.createdAt)
      analytics.track(
        AnalyticsEvent.expenseLogged,
        properties: [
          AnalyticsProperty.period: period.analyticsValue,
          AnalyticsProperty.isAddFunds: expense.isAddFunds,
          AnalyticsProperty.fromScreen: "add_sheet",
          AnalyticsProperty.timeSinceBudgetCreatedBucket: timeSinceBudgetCreatedBucket(
            seconds: elapsed
          ),
        ]
      )

    case let .edit(expense):
      var changed = false
      // Compare against displayAmount (absolute value) — mirrors how the field is seeded.
      // Write preserves sign for isAddFunds rows (spec: "Edit-mode Save preserves the sign of ExpenseItem.amount").
      if let newAmount = amount, expense.displayAmount != newAmount {
        expense.amount = expense.isAddFunds ? -newAmount : newAmount
        changed = true
      }
      if expense.name != trimmedName {
        expense.name = trimmedName
        changed = true
      }
      // .minute granularity matches the picker's .hourAndMinute resolution (spec decision 6)
      if !Calendar.current.isDate(expense.date, equalTo: date, toGranularity: .minute) {
        expense.date = date
        changed = true
      }
      if changed {
        let now = Date()
        expense.lastModified = now
        expense.budget?.lastModified = now
        try? context.save()
        // expense_edited: NO ExpenseItem field transmitted — only categorical context.
        let budget = expense.budget
        let period = budget.map { BudgetPeriod(rawValue: $0.period) ?? .daily } ?? .daily
        analytics.track(
          AnalyticsEvent.expenseEdited,
          properties: [
            AnalyticsProperty.period: period.analyticsValue,
            AnalyticsProperty.isAddFunds: expense.isAddFunds,
            AnalyticsProperty.fromScreen: "budget_detail",
          ]
        )
      }
    }
  }

  func delete(context: ModelContext) {
    guard case let .edit(expense) = mode else { return }
    let budget = expense.budget
    context.delete(expense)
    budget?.lastModified = Date()
    try? context.save()
  }
}

// MARK: - View

struct AddEditExpenseView: View {
  @State var viewModel: AddEditExpenseViewModel
  @Environment(\.modelContext) private var context
  @Environment(AppSettings.self) private var settings
  @Environment(\.analytics) private var analytics
  @Environment(\.dismiss) private var dismiss

  @State private var showDeleteConfirmation = false
  @FocusState private var isAmountFocused: Bool

  var body: some View {
    ScrollView {
      VStack(spacing: 16) {
        amountCard
        nameCard
        whenCard
        if viewModel.isEditing {
          deleteButton
        }
      }
      .padding(.horizontal)
      .padding(.top, 8)
      .padding(.bottom, 32)
    }
    .onAppear {
      // Auto-focus Amount in Add mode only; Edit/View mode should not pop the keyboard
      // (spec: "Add mode auto-focuses the Amount field; Edit/View mode does not")
      if !viewModel.isEditing {
        isAmountFocused = true
      }
    }
    .navigationTitle(
      viewModel.isEditing
        ? String(
          localized: "addEditExpense.title.existing",
          defaultValue: "Expense",
          comment:
          "Navigation bar title for an existing expense (F-2.04: same surface for view and in-place edit; no separate Edit mode)"
        )
        : String(
          localized: "addEditExpense.title.add",
          defaultValue: "Add Expense",
          comment: "Navigation bar title when adding a new expense"
        )
    )
    .navigationBarTitleDisplayMode(.inline)
    .appBackground()
    .toolbar {
      if !viewModel.isEditing {
        ToolbarItem(placement: .cancellationAction) {
          Button(String(
            localized: "addEditExpense.action.cancel",
            defaultValue: "Cancel",
            comment: "Button that dismisses the Add/Edit Expense sheet without saving"
          )) {
            dismiss()
          }
        }
      }
      ToolbarItem(placement: .confirmationAction) {
        Button(String(
          localized: "addEditExpense.action.save",
          defaultValue: "Save",
          comment: "Button that saves the expense and dismisses the sheet"
        )) {
          viewModel.save(context: context, analytics: analytics)
          dismiss()
        }
        .disabled(!viewModel.canSave)
        .fontWeight(.semibold)
        .tint(.accentColor)
      }
    }
  }

  // MARK: - Destructive Actions

  private var deleteButton: some View {
    Button(role: .destructive) {
      showDeleteConfirmation = true
    } label: {
      Text(String(
        localized: "addEditExpense.action.delete",
        defaultValue: "Delete Expense",
        comment: "Button that triggers the delete expense confirmation dialog"
      ))
      .frame(maxWidth: .infinity)
    }
    .buttonStyle(.bordered)
    .tint(.red)
    .accessibilityHint(String(
      localized: "addEditExpense.action.delete.accessibilityHint",
      defaultValue: "Permanently deletes this expense.",
      comment: "VoiceOver hint for the Delete Expense button"
    ))
    .confirmationDialog(
      String(
        localized: "addEditExpense.deleteConfirmation.title",
        defaultValue: "Delete Expense?",
        comment: "Title of the confirmation dialog when the user taps Delete Expense"
      ),
      isPresented: $showDeleteConfirmation,
      titleVisibility: .visible
    ) {
      Button(
        String(
          localized: "addEditExpense.deleteConfirmation.confirm",
          defaultValue: "Delete Expense",
          comment: "Destructive confirm button in the delete expense confirmation dialog"
        ),
        role: .destructive
      ) {
        viewModel.delete(context: context)
        dismiss()
      }
    } message: {
      Text(String(
        localized: "addEditExpense.deleteConfirmation.message",
        defaultValue: "This action cannot be undone.",
        comment: "Body text in the delete expense confirmation dialog"
      ))
    }
  }

  // MARK: - Cards

  private var amountCard: some View {
    GroupBox {
      HStack(alignment: .firstTextBaseline, spacing: 2) {
        Text(currencyPrefix)
          .font(.title2.weight(.semibold))
          .foregroundStyle(.secondary)
        TextField(
          String(
            localized: "addEditExpense.field.amount.placeholder",
            defaultValue: "0",
            comment: "Placeholder in the expense amount field when no value is entered"
          ),
          value: $viewModel.amount,
          format: OptionalDecimalFormatStyle()
        )
        .keyboardType(.decimalPad)
        .font(.title2.weight(.semibold).monospacedDigit())
        .focused($isAmountFocused)
        .accessibilityLabel(String(
          localized: "addEditExpense.field.amount.accessibilityLabel",
          defaultValue: "Expense amount",
          comment: "VoiceOver label for the expense amount field"
        ))
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    } label: {
      sectionLabel(String(
        localized: "addEditExpense.section.amount",
        defaultValue: "Amount",
        comment: "Section header above the expense amount field"
      ))
    }
    .backgroundStyle(Color("CellBackground"))
  }

  private var nameCard: some View {
    GroupBox {
      TextField(
        String(
          localized: "addEditExpense.field.name.placeholder",
          defaultValue: "e.g. Coffee",
          comment: "Placeholder text for the expense description field"
        ),
        text: $viewModel.name
      )
      .font(.body)
      .accessibilityLabel(String(
        localized: "addEditExpense.field.name.accessibilityLabel",
        defaultValue: "Expense description",
        comment: "VoiceOver label for the expense description text field"
      ))
    } label: {
      sectionLabel(String(
        localized: "addEditExpense.section.name",
        defaultValue: "Description (optional)",
        comment: "Section header above the expense description field"
      ))
    }
    .backgroundStyle(Color("CellBackground"))
  }

  private var whenCard: some View {
    GroupBox {
      DatePicker(
        String(
          localized: "addEditExpense.field.date.label",
          defaultValue: "When",
          comment: "Label for the expense date and time picker"
        ),
        selection: $viewModel.date,
        in: viewModel.dateRange,
        displayedComponents: [.date, .hourAndMinute]
      )
      .datePickerStyle(.compact)
      .labelsHidden()
      .frame(maxWidth: .infinity, alignment: .leading)
      if let caption = viewModel.pausedCaption {
        Text(caption)
          .font(.caption)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    } label: {
      sectionLabel(String(
        localized: "addEditExpense.section.when",
        defaultValue: "When",
        comment: "Section header above the expense date and time picker"
      ))
    }
    .backgroundStyle(Color("CellBackground"))
  }

  // MARK: - Helpers

  private var currencyPrefix: String {
    settings.currencyDisplay.prefix(for: viewModel.currencyCode)
  }

  private func sectionLabel(_ text: String) -> some View {
    Text(text)
      .font(.subheadline)
      .foregroundStyle(.secondary)
  }
}

// MARK: - Previews

#if DEBUG
  #Preview("Add — Light") {
    NavigationStack {
      AddEditExpenseView(viewModel: AddEditExpenseViewModel(adding: DebugData.dailyDefault()))
    }
    .modelContainer(PreviewContainer.make())
    .environment(AppSettings())
  }

  #Preview("Add — Dark") {
    NavigationStack {
      AddEditExpenseView(viewModel: AddEditExpenseViewModel(adding: DebugData.weeklyDefault()))
    }
    .modelContainer(PreviewContainer.make())
    .environment(AppSettings())
    .preferredColorScheme(.dark)
  }

  #Preview("Existing expense — Light") {
    let budget = DebugData.dailyDefault()
    return NavigationStack {
      AddEditExpenseView(
        viewModel: AddEditExpenseViewModel(editing: budget.expenseItems[0])
      )
    }
    .modelContainer(PreviewContainer.make())
    .environment(AppSettings())
  }

  #Preview("Existing expense — Dark") {
    let budget = DebugData.monthlyDefault()
    return NavigationStack {
      AddEditExpenseView(
        viewModel: AddEditExpenseViewModel(editing: budget.expenseItems[0])
      )
    }
    .modelContainer(PreviewContainer.make())
    .environment(AppSettings())
    .preferredColorScheme(.dark)
  }

  #Preview("xxxLarge Type") {
    NavigationStack {
      AddEditExpenseView(viewModel: AddEditExpenseViewModel(adding: DebugData.dailyDefault()))
    }
    .modelContainer(PreviewContainer.make())
    .environment(AppSettings())
    .dynamicTypeSize(.xxxLarge)
  }

  #Preview("Empty — Save disabled") {
    let vm = AddEditExpenseViewModel(adding: DebugData.dailyDefault())
    vm.amount = nil
    return NavigationStack {
      AddEditExpenseView(viewModel: vm)
    }
    .modelContainer(PreviewContainer.make())
    .environment(AppSettings())
  }
#endif
