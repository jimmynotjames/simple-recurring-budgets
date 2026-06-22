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

  /// Who last wrote the `amount` draft. Drives the F-7.04 smart-apply rule in
  /// `applyRecent`: a Recents tap only writes `amount` when the draft is `.empty` or
  /// `.tileSeeded` — fresher user keystrokes always win over staler suggestion data,
  /// and a silent overwrite the user might not notice before Save is the failure mode
  /// this exists to prevent.
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
      // Classify the write. Skipped for tile seeds (`applyRecent` sets the flag and
      // classifies as `.tileSeeded` itself) and for echo writes — after an external
      // write, `CurrencyAmountField` re-seeds its text and re-parses it back through
      // the binding with an equal value, which must not be mistaken for typing.
      guard !isSeedingAmountFromSuggestion, amount != oldValue else { return }
      amountProvenance = amount == nil ? .empty : .userTyped
    }
  }

  /// See `AmountProvenance`. Internal (not `private(set)`) because `applyRecent` lives
  /// in `AddEditExpenseView+RecentsSection.swift` and reclassifies on tile seed.
  @ObservationIgnored var amountProvenance: AmountProvenance = .empty
  /// True while `applyRecent` writes `amount`, so the property observer above doesn't
  /// classify the tile seed as user typing. Internal for the same cross-file reason.
  @ObservationIgnored var isSeedingAmountFromSuggestion = false

  var name: String {
    didSet {
      // Set the Edit-mode reveal latch whenever the Description becomes blank mid-session
      // (one-way: never reset to false). Drives shouldShowRecentsSection in Edit mode.
      // Guard is a fast-path; the latch write is a no-op once true.
      if !recentsRevealedInEdit,
         name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        recentsRevealedInEdit = true
      }
    }
  }

  /// F-7.04 Edit-mode reveal latch. `true` once the Description draft has ever been blank
  /// (trimmed empty) during this sheet's lifetime — either because the expense opened with
  /// a nil/whitespace name, or because the user cleared it mid-session. One-way: never
  /// reverts to `false`. When `true`, `shouldShowRecentsSection` shows Recents in Edit mode
  /// identically to Add mode (same corpus, filter, tiles, and tap semantics).
  private(set) var recentsRevealedInEdit = false

  var date: Date
  let currencyCode: String

  /// F-6.01 Add Funds toggle state. Drives the navigation title flip, the amount-text
  /// tint, the Description default-seed behavior, and the sign of `ExpenseItem.amount`
  /// on Save in both Add and Edit mode.
  var isAddFunds: Bool = false {
    didSet {
      guard isAddFunds, !oldValue else { return }
      // Seed the description with a sensible default the first time the user toggles
      // Add Funds on, but only if the field is empty/whitespace — never overwrite
      // user-entered text. Intentionally one-way: toggling back off does not clear it.
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

  /// Captured at init: the global week-start day (`AppSettings.weekStartDay`) threaded
  /// into every `BudgetCalculator.snapshot` call this VM makes. A plain `Weekday` value
  /// (not `AppSettings`) per the add-edit-expense-screen spec's no-stored-settings rule.
  /// Like `cachedBudgetSnapshot`, it does not track setting changes made while the
  /// sheet is open.
  private let weekStart: Weekday

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

  /// Cached at init: the abbreviated rendering of `Budget.startDate` for the
  /// pre-start clamped-default caption (F-2.04). `nil` outside the pre-start case.
  private let cachedStartDateFormatted: String?

  /// Cached at init: the abbreviated rendering of `Budget.endDate` for the
  /// post-end clamped-default caption (F-2.04). `nil` outside the post-end case.
  private let cachedEndDateFormatted: String?

  /// F-7.04 Recents search corpus, memoized at sheet-open: up to `recentsCorpusLimit`
  /// candidate tiles. Typing filters this full corpus; `filteredRecentSuggestions`
  /// applies the smaller `recentsDisplayLimit` cap to what's rendered. Recomputing
  /// during typing would re-aggregate `budget.expenseItems` on every keystroke; caching
  /// reduces the per-keystroke filter cost to O(C). Always populated (including Edit
  /// mode, where the section is hidden) so a future presentation change doesn't strand
  /// a stale empty. See `AddEditExpenseView+RecentsSection.swift` for the algorithm.
  let cachedRecentCandidates: [RecentExpenseSuggestion]

  var isEditing: Bool {
    if case .edit = mode { return true }
    return false
  }

  /// The budget driving this expense entry. Used for date-bounds validation and (since
  /// F-7.04) the Recents-section candidate query in `AddEditExpenseView+RecentsSection.swift`.
  var budget: Budget? {
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
      budget: budget, expenses: [], now: date, calendar: .autoupdatingCurrent, weekStart: weekStart
    )
    return snapAtDate.lifecycleState == .active
  }

  /// The single caption rendered below the When card. Resolved in priority order:
  ///
  /// 1. Paused + date out of range → "Pick a date within an active period of this budget."
  /// 2. Paused + date valid → "Paused since {date}. You can still add expenses dated before then."
  /// 3. Add mode + pre-start (`now < startDate`) → "Budget starts on {startDate}." (F-2.04)
  /// 4. Add mode + post-end (`now > endDate`) → "Budget ended on {endDate}." (F-2.04)
  /// 5. Otherwise → `nil`.
  ///
  /// The pre-start / post-end captions are intentionally **Add-mode only**: in Edit
  /// mode the existing expense already carries its stored date, so the clamped-default
  /// rationale doesn't apply. They also persist for the sheet's lifetime in those
  /// lifecycle states — they're not gated on whether the picker still shows the clamped
  /// default — since the underlying `[startDate, endDate]` constraint still applies
  /// after the user edits the field.
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

  /// The allowed range for `date` in the picker. Lower bound is the owning budget's
  /// `effectiveStartDate`. When the budget is paused, the upper bound is the most
  /// recent `.pause` event's `effectiveDate` (a moment guaranteed to lie inside an
  /// active period since the pause-action period is itself active). Save-time
  /// validation catches dates inside paused gaps for multi-cycle histories.
  ///
  /// For `.specificDates` budgets, the upper bound is the **last moment of `endDate`'s
  /// day** (not `startOfDay(endDate)`). Per the `Budget.endDate` convention, `endDate`
  /// is the inclusive last day of the window — clamping the picker at start-of-day
  /// would exclude most of that day from the user's last-day picker entries.
  var dateRange: ClosedRange<Date> {
    guard let budget else {
      return Date.distantPast ... Date.distantFuture
    }
    let calendar = Calendar.autoupdatingCurrent
    let lower = budget.effectiveStartDate
    let pauseUpper: Date? = cachedBudgetSnapshot?.lifecycleState == .paused
      ? cachedPauseEffectiveDate
      : nil
    // Last moment of endDate's day: midnight of (endDate + 1 day) minus one second.
    // Matches `BudgetCalculator.effectiveEndExclusive`'s "include all of endDate's day"
    // semantic. Without this expansion, the picker rejects any expense time other
    // than 00:00 on `endDate`.
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
    // Defense-in-depth: `Budget.isWindowValid` ensures `endDate >= effectiveStartDate`
    // for a healthy record; trip in debug if we ever build a range from an inverted
    // window (e.g., partial CloudKit sync). In release, `max(lower, upper)` collapses
    // the range to a single point so the date picker can't crash.
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
    // Seed `date` so the picker opens inside `dateRange`:
    // - Paused: most recent pause moment (guaranteed inside an active period).
    // - Post-end: end of `endDate`'s day, matching `dateRange`'s upper bound (F-2.04).
    // - Pre-start / active / default: today, floored at `effectiveStartDate`.
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
    // Classify the seeded amount as user-typed so a single Recents tile tap fills the
    // Description only and leaves the existing amount untouched. (The init-phase assignment
    // above skips `didSet`, defaulting provenance to `.empty`; we correct that here.)
    amountProvenance = .userTyped
    name = expense.name ?? ""
    // Seed the reveal latch: if the stored description was blank, show Recents immediately.
    // Init-phase `name` assignment skips the `didSet`, so we set the latch explicitly.
    recentsRevealedInEdit = (expense.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    date = expense.date
    currencyCode = expense.budget?.currencyCode ?? (Locale.current.currency?.identifier ?? "USD")
    mode = .edit(expense)
    self.weekStart = weekStart
    // Seed F-6.01 toggle from the existing row so the title, amount tint, and Add Funds
    // card all reflect the row the user tapped on. Bypasses the didSet (which seeds
    // a default description) by assigning before the property's initial value matters.
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
    // Pre-start / post-end captions are Add-mode-only (F-2.04) — Edit mode never reads these.
    cachedStartDateFormatted = nil
    cachedEndDateFormatted = nil
    cachedRecentCandidates = Self.computeRecentCandidates(for: expense.budget)
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

  /// The navigation bar title selected from the `isEditing × isAddFunds` matrix (F-6.01).
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
    // Trim whitespace; empty-after-trim collapses to nil (spec: "Form fields are Amount, Description, and When")
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedName: String? = trimmed.isEmpty ? nil : trimmed
    switch mode {
    case let .add(budget):
      // Guard per spec: "Save in Add mode inserts a new ExpenseItem attached to the in-flight Budget"
      guard canSave, let amount else { return }
      let now = Date()
      // F-6.01: sign the persisted amount per the Add Funds toggle. The user-visible
      // Amount field is always non-negative; the toggle encodes the sign.
      let signedAmount: Decimal = isAddFunds ? -amount : amount
      let expense = ExpenseItem(amount: signedAmount, name: trimmedName, date: date)
      expense.budget = budget
      context.insert(expense)
      budget.lastModified = now
      try context.saveChanges(operation: .expenseCreate, analytics: analytics)

      // expense_logged fires only on a successful save (per `add-edit-expense-screen` delta spec).
      // NO ExpenseItem field transmitted — only categorical context.
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
      // F-6.01: sign per the draft `isAddFunds` so an Edit-mode toggle flip rewrites
      // the sign even when the magnitude is unchanged.
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
      // .minute granularity matches the picker's .hourAndMinute resolution (spec decision 6)
      if !Calendar.current.isDate(expense.date, equalTo: date, toGranularity: .minute) {
        expense.date = date
        changed = true
      }
      if changed {
        let now = Date()
        expense.lastModified = now
        expense.budget?.lastModified = now
        try context.saveChanges(operation: .expenseEdit, analytics: analytics)
        // expense_edited fires only on a successful save (per `add-edit-expense-screen` delta spec).
        // NO ExpenseItem field transmitted — only categorical context.
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
