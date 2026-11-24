import SwiftData
import SwiftUI

// MARK: - AddEditExpenseViewModel

@Observable
@MainActor
final class AddEditExpenseViewModel {
  private enum Mode {
    case add(Budget)
    case edit(ExpenseItem)
  }

  /// Who last wrote the `amount` draft (F-7.04 smart-apply). `applyRecent` writes `amount` only when this is
  /// `.empty` or `.tileSeeded`, so user keystrokes are never silently overwritten.
  enum AmountProvenance {
    /// No amount in the draft (initial state, or the user cleared/deleted it).
    case empty
    /// The user typed (or edited to) the current amount this session.
    case userTyped
    /// A Recents tile seeded the current amount; a later tile tap may replace it.
    case tileSeeded
  }

  var amount: Decimal? {
    didSet {
      // Skipped for tile seeds (`applyRecent` classifies those) and for echo writes: after
      // an external write, `CurrencyAmountField` re-parses its text back through the binding
      // with an equal value, which must not count as typing.
      guard !isSeedingAmountFromSuggestion, amount != oldValue else { return }
      amountProvenance = amount == nil ? .empty : .userTyped
    }
  }

  /// See `AmountProvenance`. Internal (not `private(set)`) because the Recents extension
  /// in another file reclassifies it on tile seed.
  @ObservationIgnored var amountProvenance: AmountProvenance = .empty
  /// True while a tile seed writes `amount`, so `didSet` doesn't treat it as typing.
  /// Internal for the same cross-file reason.
  @ObservationIgnored var isSeedingAmountFromSuggestion = false

  var name: String {
    didSet {
      // One-way latch: set when the Description goes blank, never reset. The guard is
      // just a fast path.
      if !recentsRevealedInEdit,
         name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        recentsRevealedInEdit = true
      }
    }
  }

  /// F-7.04 Edit-mode Recents reveal latch: true once the Description has been blank (trimmed)
  /// at any point in the sheet's lifetime, either at open or after the user cleared it.
  /// Never reverts. See `shouldShowRecentsSection`.
  private(set) var recentsRevealedInEdit = false

  var date: Date
  let currencyCode: String

  /// Add Funds toggle (F-6.01). Drives the title flip, amount tint, Description default seed, and
  /// the sign of `ExpenseItem.amount` on Save (Add and Edit).
  var isAddFunds: Bool = false {
    didSet {
      guard isAddFunds, !oldValue else { return }
      // Seed a default description only when blank; never overwrite user text. One-way:
      // toggling off doesn't clear it.
      let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.isEmpty {
        name = String(
          localized: "addEditExpense.field.name.addFundsDefault",
          defaultValue: "Add funds",
          comment: "Default description seeded into the Description field when the user toggles Add Funds on with an empty description (F-6.01)"
        )
      }
    }
  }

  private let mode: Mode

  /// Global week-start day, captured at init and passed to every `BudgetCalculator.snapshot`
  /// call. A plain `Weekday` (not `AppSettings`, per the add-edit-expense-screen spec's no-stored-settings rule); doesn't track changes while the sheet is open.
  private let weekStart: Weekday

  /// Lifecycle snapshot at sheet-open, cached to avoid recomputing per body pass. `nil`
  /// when no budget is reachable (orphan edit).
  private let cachedBudgetSnapshot: BudgetSnapshot?

  /// Effective date of the latest unresumed `.pause`; seeds `date` and is the picker's
  /// upper bound while paused.
  private let cachedPauseEffectiveDate: Date?

  /// Abbreviated `cachedPauseEffectiveDate` for the paused caption (cached to avoid
  /// re-formatting per body pass).
  private let cachedPausedSinceFormatted: String?

  /// Abbreviated `Budget.startDate` for the pre-start clamped-default caption (F-2.04); `nil` otherwise.
  private let cachedStartDateFormatted: String?

  /// Abbreviated `Budget.endDate` for the post-end clamped-default caption (F-2.04); `nil` otherwise.
  private let cachedEndDateFormatted: String?

  /// F-7.04 Recents search corpus (up to `recentsCorpusLimit` tiles), memoized at sheet-open so
  /// typing filters it without re-aggregating `budget.expenseItems` per keystroke. Populated
  /// in Edit mode too. Algorithm in `AddEditExpenseView+RecentsSection.swift`.
  let cachedRecentCandidates: [RecentExpenseSuggestion]

  var isEditing: Bool {
    if case .edit = mode {
      return true
    }
    return false
  }

  /// The budget driving this entry; used for date-bounds validation and F-7.04 Recents candidates.
  var budget: Budget? {
    switch mode {
    case let .add(budget): budget
    case let .edit(expense): expense.budget
    }
  }

  /// True when `date` lies in an active-period interval (or the budget isn't paused).
  /// Gates Save; the paused caption doesn't use it.
  private var isDateValid: Bool {
    guard let budget, cachedBudgetSnapshot?.lifecycleState == .paused else { return true }
    let snapAtDate = BudgetCalculator.snapshot(
      budget: budget, expenses: [], now: date, calendar: .autoupdatingCurrent, weekStart: weekStart
    )
    return snapAtDate.lifecycleState == .active
  }

  /// The caption below the When card, first match wins: paused + date out of range;
  /// paused + date valid ("Paused since…"); Add mode pre-start ("Budget starts on…",
  /// F-2.04); Add mode post-end ("Budget ended on…", F-2.04); otherwise `nil`.
  ///
  /// Pre-start/post-end are Add-mode only (Edit already has a stored date). They persist for
  /// the sheet's lifetime, not just while the picker shows the clamped default, because
  /// the `[startDate, endDate]` constraint still applies after the user edits.
  var dateContextCaption: String? {
    if cachedBudgetSnapshot?.lifecycleState == .paused {
      if !isDateValid {
        return String(
          localized: "addEditExpense.date.outOfRange.caption",
          defaultValue: "Pick a date within an active period of this budget.",
          comment: "Inline caption below the date picker when the selected date falls inside a paused period"
        )
      }
      if let formatted = cachedPausedSinceFormatted {
        return String(
          localized: "addEditExpense.paused.caption.format",
          defaultValue: "Paused since \(formatted). You can still add expenses dated before then.",
          comment: "Proactive caption shown below the When card in Add/Edit Expense when the bound budget is paused; argument is the abbreviated pausedSince date"
        )
      }
      return nil
    }
    guard !isEditing else { return nil }
    switch cachedBudgetSnapshot?.lifecycleState {
    case .preStart:
      guard let formatted = cachedStartDateFormatted else { return nil }
      return String(
        localized: "addEditExpense.preStart.caption.format",
        defaultValue: "Budget starts on \(formatted).",
        comment: "Inline caption below the When card in Add Expense when the bound budget is pre-start (now < startDate); argument is the abbreviated start date. Explains why the date picker default isn't today."
      )
    case .postEnd:
      guard let formatted = cachedEndDateFormatted else { return nil }
      return String(
        localized: "addEditExpense.postEnd.caption.format",
        defaultValue: "Budget ended on \(formatted).",
        comment: "Inline caption below the When card in Add Expense when the bound budget is post-end (now > endDate); argument is the abbreviated end date. Explains why the date picker default isn't today."
      )
    case .active, .paused, .none:
      return nil
    }
  }

  var canSave: Bool {
    guard (amount ?? 0) > 0 else { return false }
    return isDateValid
  }

  /// Allowed picker range. Lower bound is `effectiveStartDate`. While paused, the upper
  /// bound is the latest `.pause` event's `effectiveDate` (inside an active period);
  /// `isDateValid` catches dates in earlier paused gaps at save time.
  ///
  /// For `.specificDates` budgets the upper bound is the last moment of `endDate`'s day, not
  /// start-of-day: `endDate` is the inclusive last day, so start-of-day would exclude
  /// nearly all of it.
  var dateRange: ClosedRange<Date> {
    guard let budget else {
      return Date.distantPast ... Date.distantFuture
    }
    let calendar = Calendar.autoupdatingCurrent
    let lower = budget.effectiveStartDate
    let pauseUpper: Date? = cachedBudgetSnapshot?.lifecycleState == .paused
      ? cachedPauseEffectiveDate
      : nil
    // Next midnight minus 1s: includes all of endDate's day, matching
    // `BudgetCalculator.effectiveEndExclusive`.
    let endUpper: Date? = budget.endDate.map { endDate in
      let nextDayStart = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endDate))!
      return nextDayStart.addingTimeInterval(-1)
    }
    let upper: Date = switch (pauseUpper, endUpper) {
    case let (.some(p), .some(e)): min(p, e)
    case let (.some(p), .none): p
    case let (.none, .some(e)): e
    case (.none, .none): Date.distantFuture
    }
    // Defense-in-depth: asserts in debug on an inverted window (e.g. partial CloudKit
    // sync). Release relies on `max(lower, upper)` collapsing to a point so the picker
    // can't crash on an invalid ClosedRange. Keep both.
    assert(budget.isWindowValid, "AddEditExpenseView.dateRange: inverted budget window — endDate < effectiveStartDate")
    return lower ... max(lower, upper)
  }

  init(adding budget: Budget, weekStart: Weekday) {
    amount = nil
    name = ""
    currencyCode = budget.currencyCode
    mode = .add(budget)
    self.weekStart = weekStart
    let snapshot = BudgetCalculator.snapshot(
      budget: budget, expenses: [], now: Date(), calendar: .autoupdatingCurrent, weekStart: weekStart
    )
    cachedBudgetSnapshot = snapshot
    let pauseDate = Self.latestPauseEffectiveDate(for: budget)
    cachedPauseEffectiveDate = pauseDate
    cachedPausedSinceFormatted = pauseDate?.formatted(date: .abbreviated, time: .omitted)
    cachedStartDateFormatted = snapshot.lifecycleState == .preStart
      ? budget.startDate?.formatted(date: .abbreviated, time: .omitted)
      : nil
    cachedEndDateFormatted = snapshot.lifecycleState == .postEnd
      ? budget.endDate?.formatted(date: .abbreviated, time: .omitted)
      : nil
    cachedRecentCandidates = Self.computeRecentCandidates(for: budget)
    // Seed `date` inside `dateRange`: paused → latest pause moment; post-end → end of
    // `endDate`'s day (the range's upper bound, F-2.04); otherwise today floored at
    // `effectiveStartDate`.
    if snapshot.lifecycleState == .paused, let pauseDate {
      date = pauseDate
    } else if snapshot.lifecycleState == .postEnd, let endDate = budget.endDate {
      let calendar = Calendar.autoupdatingCurrent
      let nextDayStart = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endDate))!
      date = nextDayStart.addingTimeInterval(-1)
    } else {
      date = max(Date(), budget.effectiveStartDate)
    }
  }

  init(editing expense: ExpenseItem, weekStart: Weekday) {
    amount = expense.displayAmount
    // Init-phase assignments skip `didSet`, so set provenance and the reveal latch
    // explicitly: the existing amount counts as typed (a tile tap leaves it alone), and
    // a blank stored description shows Recents immediately.
    amountProvenance = .userTyped
    name = expense.name ?? ""
    recentsRevealedInEdit = (expense.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    date = expense.date
    currencyCode = expense.budget?.currencyCode ?? (Locale.current.currency?.identifier ?? "USD")
    mode = .edit(expense)
    self.weekStart = weekStart
    // Seeds the F-6.01 toggle from the stored row; init-phase assignment skips the `didSet`
    // that would seed a default description.
    isAddFunds = expense.isAddFunds
    if let budget = expense.budget {
      cachedBudgetSnapshot = BudgetCalculator.snapshot(
        budget: budget, expenses: [], now: Date(), calendar: .autoupdatingCurrent, weekStart: weekStart
      )
      let pauseDate = Self.latestPauseEffectiveDate(for: budget)
      cachedPauseEffectiveDate = pauseDate
      cachedPausedSinceFormatted = pauseDate?.formatted(date: .abbreviated, time: .omitted)
    } else {
      cachedBudgetSnapshot = nil
      cachedPauseEffectiveDate = nil
      cachedPausedSinceFormatted = nil
    }
    // Pre-start / post-end captions are Add-mode only (F-2.04).
    cachedStartDateFormatted = nil
    cachedEndDateFormatted = nil
    cachedRecentCandidates = Self.computeRecentCandidates(for: expense.budget)
  }

  /// `effectiveDate` of the latest `.pause` not followed by a `.resume`. Mirrors
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

  /// Navigation title for the `isEditing × isAddFunds` combination (F-6.01).
  var navigationTitle: String {
    switch (isEditing, isAddFunds) {
    case (false, false):
      String(localized: "addEditExpense.title.add", defaultValue: "Add Expense", comment: "Navigation bar title when adding a new expense")
    case (false, true):
      String(localized: "addEditExpense.title.add.addFunds", defaultValue: "Add Funds", comment: "Navigation bar title when adding funds (F-6.01)")
    case (true, false):
      String(localized: "addEditExpense.title.existing", defaultValue: "Expense", comment: "Navigation bar title for an existing expense (F-2.04)")
    case (true, true):
      String(localized: "addEditExpense.title.existing.addFunds", defaultValue: "Add Funds", comment: "Navigation bar title for an existing add-funds entry (F-6.01)")
    }
  }

  /// Convenience overload for tests and call sites without an `AnalyticsClient` in scope.
  func save(context: ModelContext) throws {
    try save(context: context, analytics: ConsoleAnalyticsClient())
  }

  func save(context: ModelContext, analytics: any AnalyticsClient) throws {
    // Empty-after-trim name collapses to nil.
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedName: String? = trimmed.isEmpty ? nil : trimmed
    switch mode {
    case let .add(budget):
      guard canSave, let amount else { return }
      let now = Date()
      // F-6.01: the Amount field is always non-negative; the Add Funds toggle encodes the sign.
      let signedAmount: Decimal = isAddFunds ? -amount : amount
      let expense = ExpenseItem(amount: signedAmount, name: trimmedName, date: date)
      expense.budget = budget
      context.insert(expense)
      budget.lastModified = now
      try context.saveChanges(operation: .expenseCreate, analytics: analytics)

      // Fires only after a successful save; categorical properties only, no expense fields.
      let period = budget.periodEnum
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
      // F-6.01: sign follows the draft `isAddFunds`, so a toggle flip rewrites the sign even
      // when the magnitude is unchanged.
      if let newAmount = amount {
        let desired: Decimal = isAddFunds ? -newAmount : newAmount
        if expense.amount != desired {
          expense.amount = desired
          changed = true
        }
      }
      if expense.name != trimmedName {
        expense.name = trimmedName
        changed = true
      }
      // .minute granularity matches the picker's .hourAndMinute resolution.
      if !Calendar.current.isDate(expense.date, equalTo: date, toGranularity: .minute) {
        expense.date = date
        changed = true
      }
      if changed {
        let now = Date()
        expense.lastModified = now
        expense.budget?.lastModified = now
        try context.saveChanges(operation: .expenseEdit, analytics: analytics)
        // Fires only after a successful save; categorical properties only.
        let budget = expense.budget
        let period = budget?.periodEnum ?? .daily
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

  /// Convenience overload for tests and call sites without an `AnalyticsClient` in scope.
  func delete(context: ModelContext) throws {
    try delete(context: context, analytics: ConsoleAnalyticsClient())
  }

  func delete(context: ModelContext, analytics: any AnalyticsClient) throws {
    guard case let .edit(expense) = mode else { return }
    let budget = expense.budget
    context.delete(expense)
    budget?.lastModified = Date()
    try context.saveChanges(operation: .expenseDelete, analytics: analytics)
  }
}
