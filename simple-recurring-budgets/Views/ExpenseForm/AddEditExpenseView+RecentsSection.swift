import SwiftData
import SwiftUI

// MARK: - Suggestion value type

/// Condensed prior `ExpenseItem` used as an F-7.04 Recents suggestion. Identity is the source
/// expense's `persistentModelID`, so duplicate name + amount pairs stay distinct rows.
struct RecentExpenseSuggestion: Identifiable, Hashable {
  let id: PersistentIdentifier
  let name: String
  let amount: Decimal
}

// MARK: - ViewModel: candidate set, filter, and apply

extension AddEditExpenseViewModel {
  /// Max tiles displayed at once, both with an empty query and after filtering. The
  /// filter searches the full corpus (`recentsCorpusLimit`), then this cap trims what's
  /// rendered. Large enough that infrequent picks (a weekly croissant) still appear on
  /// dense budgets.
  static let recentsDisplayLimit: Int = 30

  /// Max candidates in the memoized search corpus. Typing filters this full set, not
  /// just the displayed row. Bounds sheet-open memoization and the per-keystroke substring
  /// filter; ~200 unique names covers a year+ of realistic logging.
  static let recentsCorpusLimit: Int = 200

  /// How many times an exact (name, amount) pair must recur to earn an extra variant tile
  /// beyond its name's base tile. Filters coincidental repeats; real fixtures (small and
  /// large coffee) qualify within weeks. The base (most recent) amount per name always shows.
  static let variantRecurrenceThreshold: Int = 3

  /// Max extra variant tiles per name beyond the base (so ≤3 tiles share a name), so one
  /// multi-price fixture can't crowd out other names.
  static let maxVariantsPerName: Int = 2

  /// Builds the recents candidate corpus from a budget's expense history. Pure; called
  /// from `AddEditExpenseViewModel.init` to populate `cachedRecentCandidates`.
  ///
  /// - Pass 1: aggregate into (folded name, amount) pairs with occurrence count and most
  ///   recent occurrence. Names fold case- and diacritic-insensitively ("Café"/"cafe"),
  ///   matching the typed-query filter's equivalence.
  /// - Pass 2: per name, the most recent pair is the base tile; other pairs become variant
  ///   tiles only if their count ≥ `variantRecurrenceThreshold` (max `maxVariantsPerName`).
  ///   This separates a real two-price fixture from one-off price jitter.
  /// - Pass 3: sort name groups by most recent date descending, flatten (variants directly
  ///   after their base), then `prefix(recentsCorpusLimit)`.
  ///
  /// F-7.04 exclusions: Add Funds entries (F-6.01; not meaningful as expense suggestions) and unnamed
  /// entries (bare amounts aren't actionable and would flood the row).
  static func computeRecentCandidates(
    for budget: Budget?,
    limit: Int = recentsCorpusLimit
  ) -> [RecentExpenseSuggestion] {
    guard let budget else { return [] }
    // `item` is the most recent occurrence: its model ID is the tile identity and
    // `displayName` is its trimmed name. `count` feeds the recurrence gate.
    struct PairAggregate {
      var item: ExpenseItem
      var displayName: String
      var count: Int
    }
    var byName: [String: [Decimal: PairAggregate]] = [:]
    for expense in budget.expenseItems {
      guard !expense.isAddFunds else { continue }
      let trimmed = (expense.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { continue }
      let key = foldedKey(trimmed)
      let amount = expense.displayAmount
      if var existing = byName[key]?[amount] {
        existing.count += 1
        if expense.date > existing.item.date {
          existing.item = expense
          existing.displayName = trimmed
        }
        byName[key]?[amount] = existing
      } else {
        byName[key, default: [:]][amount] = PairAggregate(
          item: expense, displayName: trimmed, count: 1
        )
      }
    }
    var groups: [[PairAggregate]] = []
    for pairs in byName.values {
      let sorted = pairs.values.sorted { $0.item.date > $1.item.date }
      guard let base = sorted.first else { continue }
      let variants = sorted.dropFirst()
        .filter { $0.count >= Self.variantRecurrenceThreshold }
        .prefix(Self.maxVariantsPerName)
      groups.append([base] + variants)
    }
    return groups
      .sorted { $0[0].item.date > $1[0].item.date }
      .flatMap(\.self)
      .prefix(limit)
      .map { record in
        RecentExpenseSuggestion(
          id: record.item.persistentModelID,
          name: record.displayName,
          amount: record.item.displayAmount
        )
      }
  }

  /// Case- and diacritic-insensitive fold ("Café" → "cafe"). Dedup key for
  /// `computeRecentCandidates`; must stay aligned with the filter's
  /// `[.caseInsensitive, .diacriticInsensitive]` match.
  fileprivate static func foldedKey(_ string: String) -> String {
    string.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
  }

  /// True when any prior expense could surface as a suggestion. Drives true-empty
  /// visibility (section hidden, per the F-7.04 edge case); distinct from `filteredRecentSuggestions.isEmpty`, which
  /// shows the "No matches" placeholder.
  var hasRecentSources: Bool {
    !cachedRecentCandidates.isEmpty
  }

  /// Tiles to render. Empty query → first `recentsDisplayLimit` corpus tiles; otherwise a
  /// case- and diacritic-insensitive substring match over the full corpus (not just the
  /// unfiltered row), capped at `recentsDisplayLimit`. Same folding as `foldedKey(_:)`.
  var filteredRecentSuggestions: [RecentExpenseSuggestion] {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return Array(cachedRecentCandidates.prefix(Self.recentsDisplayLimit))
    }
    return Array(
      cachedRecentCandidates
        .filter {
          $0.name.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
        .prefix(Self.recentsDisplayLimit)
    )
  }

  /// True when the Recents section should appear.
  /// - Add mode: whenever the budget has a candidate.
  /// - Edit/View mode: once the `recentsRevealedInEdit` latch is set (Description blank at
  ///   open, or cleared mid-session; the F-7.04 blank-Description-gated reveal). It then persists for the sheet's lifetime even if
  ///   the Description is refilled (tile tap or re-type).
  var shouldShowRecentsSection: Bool {
    hasRecentSources && (!isEditing || recentsRevealedInEdit)
  }

  /// F-7.04: applies a tapped Recents suggestion to the draft. Always writes `name` and resets
  /// Add Funds to off (a tile is a prior expense; a stale toggle could log its amount as
  /// an add-funds adjustment).
  ///
  /// `amount` is written only when its provenance is `.empty` or `.tileSeeded`. A
  /// `.userTyped` amount survives the tap: the section acts as Description autocomplete,
  /// and completing one field must not silently overwrite a sibling the user filled (an
  /// unnoticed wrong saved amount is the costly failure). To take the tile's amount
  /// anyway: clear (✕) then re-tap, or double-tap (`applyRecentFullReplace`).
  ///
  /// Date is untouched (stays today/clamped, F-2.04) and Save is not triggered. Emits
  /// `expense_recent_reused` with bucketed categorical properties only (no PII per
  /// analytics-spec.md §2.1); query length is captured before `name` is
  /// overwritten. The write to `amount` syncs back to `CurrencyAmountField` via its
  /// `lastSyncedValue` sentinel. No default-analytics overload on purpose: every call site
  /// passes the client so bucket values come from real context.
  func applyRecent(
    _ suggestion: RecentExpenseSuggestion,
    visibleCount: Int,
    tapPosition: Int,
    analytics: any AnalyticsClient
  ) {
    // Must precede the `name` overwrite below.
    let queryLengthAtTap = name.trimmingCharacters(in: .whitespacesAndNewlines).count

    isAddFunds = false
    name = suggestion.name
    if amountProvenance != .userTyped {
      seedAmount(from: suggestion)
    }

    let period = budget?.periodEnum ?? .daily
    analytics.track(
      AnalyticsEvent.expenseRecentReused,
      properties: [
        AnalyticsProperty.period: period.analyticsValue,
        AnalyticsProperty.recentsVisibleCount: recentsVisibleCountBucket(visibleCount),
        AnalyticsProperty.recentsTapPosition: recentsTapPositionBucket(tapPosition),
        AnalyticsProperty.nameQueryLength: nameQueryLengthBucket(queryLengthAtTap),
        AnalyticsProperty.fromScreen: isEditing ? "budget_detail" : "add_sheet",
      ]
    )
  }

  /// F-7.04 double-tap full replace: writes `name` and `amount` unconditionally, overriding the
  /// provenance rule. Also resets Add Funds.
  ///
  /// No analytics: the double-tap's first tap already ran `applyRecent` (the gesture fires
  /// alongside the button action), so tracking here would double-count the reuse.
  func applyRecentFullReplace(_ suggestion: RecentExpenseSuggestion) {
    isAddFunds = false
    name = suggestion.name
    seedAmount(from: suggestion)
  }

  /// Writes a suggestion's amount as a tile seed. The flag stops `amount`'s `didSet` from
  /// classifying the write as user typing; `.tileSeeded` lets a later tile tap replace it.
  private func seedAmount(from suggestion: RecentExpenseSuggestion) {
    isSeedingAmountFromSuggestion = true
    amount = suggestion.amount
    amountProvenance = .tileSeeded
    isSeedingAmountFromSuggestion = false
  }
}

// MARK: - View entry point

extension AddEditExpenseView {
  /// F-7.04 Recents section below the Description card; visibility per `shouldShowRecentsSection`.
  ///
  /// Placement is deliberate: Description doubles as the filter query, so tiles sit directly
  /// beneath it (autocomplete idiom) and the Amount card keeps the top slot.
  ///
  /// Empty states: true-empty (`hasRecentSources == false`) removes the section entirely so
  /// the form opens calmly; filter-empty keeps the card mounted with a "No matches"
  /// placeholder so the form below doesn't shift while typing.
  @ViewBuilder
  var recentsSection: some View {
    if viewModel.shouldShowRecentsSection {
      RecentsSectionView(viewModel: viewModel)
    }
  }
}

// MARK: - RecentsSectionView

/// Renders the Recents card and owns the `@ScaledMetric` geometry. A separate struct
/// because extensions can't hold the stored properties `@ScaledMetric` needs.
private struct RecentsSectionView: View {
  let viewModel: AddEditExpenseViewModel

  @Environment(AppSettings.self) private var settings
  @Environment(\.analytics) private var analytics

  /// Tile geometry scales with Dynamic Type.
  @ScaledMetric(relativeTo: .subheadline) private var tileMaxWidth: CGFloat = 180
  @ScaledMetric(relativeTo: .subheadline) private var tilePaddingHorizontal: CGFloat = 14
  @ScaledMetric(relativeTo: .subheadline) private var tilePaddingVertical: CGFloat = 11

  var body: some View {
    // Computed once per render: the VM property re-filters on every access.
    let suggestions = viewModel.filteredRecentSuggestions
    return GroupBox {
      if suggestions.isEmpty {
        placeholder
      } else {
        tileRow(suggestions: suggestions)
      }
    } label: {
      header(suggestions: suggestions)
    }
    .backgroundStyle(Color("CellBackground"))
    .animation(.snappy(duration: 0.2), value: suggestions)
  }

  // MARK: Subviews

  private func header(suggestions: [RecentExpenseSuggestion]) -> some View {
    HStack(spacing: 8) {
      Text(String(
        localized: "addEditExpense.recents.section.title",
        defaultValue: "Recents",
        comment: "Section header label above the F-7.04 Recents row in Add Expense (a horizontal list of tappable recent-expense suggestions). One word — keep terse."
      ))
      Spacer(minLength: 8)
      // Swipe-for-more hint; the count threshold is a loose overflow proxy (exact
      // detection isn't worth it). Decorative: VoiceOver's scroll behavior conveys it.
      if suggestions.count > 3 {
        Image(systemName: "arrow.right")
          .font(.caption)
          .accessibilityHidden(true)
      }
    }
    .font(.subheadline)
    .foregroundStyle(.secondary)
  }

  private func tileRow(suggestions: [RecentExpenseSuggestion]) -> some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 10) {
        ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
          tile(for: suggestion, position: index, visibleCount: suggestions.count)
        }
      }
      .padding(.bottom, 2) // breathing room below the tile row
    }
  }

  /// One Recents tile: intrinsic width capped at `tileMaxWidth`; long names truncate.
  /// Hierarchy is by color (primary name, secondary amount), not weight.
  private func tile(
    for suggestion: RecentExpenseSuggestion,
    position: Int,
    visibleCount: Int
  ) -> some View {
    let formattedAmount = suggestion.amount.formatted(
      currencyCode: viewModel.currencyCode,
      display: settings.currencyDisplay
    )
    return Button {
      viewModel.applyRecent(
        suggestion,
        visibleCount: visibleCount,
        tapPosition: position,
        analytics: analytics
      )
    } label: {
      VStack(alignment: .leading, spacing: 4) {
        Text(suggestion.name)
          .font(.subheadline)
          .foregroundStyle(.primary)
          .lineLimit(1)
        Text(formattedAmount)
          .font(.subheadline)
          .monospacedDigit()
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      .frame(maxWidth: tileMaxWidth, alignment: .leading)
      .padding(.horizontal, tilePaddingHorizontal)
      .padding(.vertical, tilePaddingVertical)
      .background(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(Color.secondary.opacity(0.12))
      )
      .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    .buttonStyle(.plain)
    // Double-tap = full replace. Deliberately `simultaneousGesture`, not a counted
    // `onTapGesture`: single taps stay instant (no ~0.3s wait for a second tap). The first
    // tap of a double-tap runs the smart apply, then the second upgrades it; same end state.
    .simultaneousGesture(
      TapGesture(count: 2).onEnded {
        viewModel.applyRecentFullReplace(suggestion)
      }
    )
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(String(
      localized: "addEditExpense.recents.tile.accessibilityLabel",
      defaultValue: "Use \(suggestion.name), \(formattedAmount)",
      comment: "VoiceOver label for an F-7.04 Recents tile in Add Expense; argument 1 is the prior expense description, argument 2 is the formatted amount. Arguments may be reordered in translation."
    ))
    .accessibilityHint(String(
      localized: "addEditExpense.recents.tile.accessibilityHint",
      defaultValue: "Fills the amount and description for review.",
      comment: "VoiceOver hint for an F-7.04 Recents tile; explains the tap populates the draft for review and does not save."
    ))
    // VoiceOver equivalent of the sighted double-tap (VO's own double-tap is activation).
    .accessibilityAction(named: String(
      localized: "addEditExpense.recents.tile.accessibilityAction.fullReplace",
      defaultValue: "Replace amount and description",
      comment: "VoiceOver custom action name on an F-7.04 Recents tile; mirrors the sighted double-tap that overwrites both fields even when the user already typed an amount."
    )) {
      viewModel.applyRecentFullReplace(suggestion)
    }
  }

  /// "No matches" label that reserves the tile row's height so the form below doesn't
  /// shift. The hidden phantom content mirrors a tile's two-line subheadline geometry
  /// (no magic height); update together with `tile(for:position:visibleCount:)`.
  private var placeholder: some View {
    ZStack(alignment: .leading) {
      VStack(alignment: .leading, spacing: 4) {
        Text(verbatim: " ").font(.subheadline)
        Text(verbatim: " ").font(.subheadline)
      }
      .padding(.horizontal, tilePaddingHorizontal)
      .padding(.vertical, tilePaddingVertical)
      .hidden()
      .accessibilityHidden(true)

      Text(String(
        localized: "addEditExpense.recents.empty.noMatches",
        defaultValue: "No matches",
        comment: "Placeholder copy inside the F-7.04 Recents card when the user's typed query filters the row to zero matches. The card stays mounted at the same height so the form doesn't shift. Two words — keep terse."
      ))
      .font(.subheadline)
      .foregroundStyle(.tertiary)
      .accessibilityLabel(String(
        localized: "addEditExpense.recents.empty.accessibilityLabel",
        defaultValue: "No matching recent expenses",
        comment: "VoiceOver label for the F-7.04 Recents empty-filter placeholder; more descriptive than the visible \"No matches\" copy so screen reader users get unambiguous context."
      ))
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

// MARK: - Previews

#if DEBUG
  #Preview("Recents — Light") {
    NavigationStack {
      AddEditExpenseView(viewModel: AddEditExpenseViewModel(adding: DebugData.dailyDefault(), weekStart: .sunday))
    }
    .modelContainer(PreviewContainer.make())
    .environment(AppSettings())
  }

  #Preview("Recents — Dark") {
    NavigationStack {
      AddEditExpenseView(viewModel: AddEditExpenseViewModel(adding: DebugData.dailyDefault(), weekStart: .sunday))
    }
    .modelContainer(PreviewContainer.make())
    .environment(AppSettings())
    .preferredColorScheme(.dark)
  }

  #Preview("Recents — Empty: no prior expenses") {
    let budget = Budget(name: "Daily — fresh", currencyCode: "USD", period: .daily)
    budget.startDate = Calendar.current.startOfDay(for: Date())
    return NavigationStack {
      AddEditExpenseView(viewModel: AddEditExpenseViewModel(adding: budget, weekStart: .sunday))
    }
    .modelContainer(PreviewContainer.make())
    .environment(AppSettings())
  }

  #Preview("Recents — Empty: no filter matches") {
    let budget = DebugData.dailyDefault()
    let vm = AddEditExpenseViewModel(adding: budget, weekStart: .sunday)
    vm.name = "Pizza"
    return NavigationStack {
      AddEditExpenseView(viewModel: vm)
    }
    .modelContainer(PreviewContainer.make())
    .environment(AppSettings())
  }

  #Preview("Recents — Long name (truncates)") {
    let budget = Budget(name: "Daily — long-name demo", currencyCode: "USD", period: .daily)
    budget.startDate = Calendar.current.startOfDay(for: Date())
    let now = Date()
    let expenses = [
      ExpenseItem(amount: 38.50, name: "Saturday brunch with friends", date: now),
      ExpenseItem(amount: 4.50, name: "Morning coffee", date: now.addingTimeInterval(-3600)),
      ExpenseItem(amount: 9.25, name: "Lunch", date: now.addingTimeInterval(-7200)),
    ]
    for expense in expenses {
      expense.budget = budget
    }
    budget.expenseItems = expenses
    return NavigationStack {
      AddEditExpenseView(viewModel: AddEditExpenseViewModel(adding: budget, weekStart: .sunday))
    }
    .modelContainer(PreviewContainer.make())
    .environment(AppSettings())
  }

  #Preview("Recents — amount variants") {
    // Expect two clustered "Coffee" tiles (4.50 base, 5.75 variant) and one "Groceries"
    // tile (jittered one-offs collapse to the most recent).
    let budget = Budget(name: "Daily — variants demo", currencyCode: "USD", period: .daily)
    let now = Date()
    budget.startDate = Calendar.current.date(byAdding: .day, value: -30, to: now)
    var expenses: [ExpenseItem] = []
    for day in 0 ..< 5 {
      expenses.append(ExpenseItem(
        amount: 4.50, name: "Coffee", date: now.addingTimeInterval(Double(-day) * 86400)
      ))
    }
    for day in 0 ..< 3 {
      expenses.append(ExpenseItem(
        amount: 5.75, name: "Coffee", date: now.addingTimeInterval(Double(-day) * 86400 - 3600)
      ))
    }
    expenses.append(ExpenseItem(amount: 87.32, name: "Groceries", date: now.addingTimeInterval(-7200)))
    expenses.append(ExpenseItem(amount: 91.10, name: "Groceries", date: now.addingTimeInterval(-93600)))
    expenses.append(ExpenseItem(amount: 103.55, name: "Groceries", date: now.addingTimeInterval(-180_000)))
    for expense in expenses {
      expense.budget = budget
    }
    budget.expenseItems = expenses
    return NavigationStack {
      AddEditExpenseView(viewModel: AddEditExpenseViewModel(adding: budget, weekStart: .sunday))
    }
    .modelContainer(PreviewContainer.make())
    .environment(AppSettings())
  }

  #Preview("Recents — Edit mode, non-blank (no section)") {
    // Non-blank description: latch not set, section stays hidden.
    let budget = DebugData.dailyDefault()
    return NavigationStack {
      AddEditExpenseView(viewModel: AddEditExpenseViewModel(editing: budget.expenseItems[0], weekStart: .sunday))
    }
    .modelContainer(PreviewContainer.make())
    .environment(AppSettings())
  }

  #Preview("Recents — Edit mode, blank description (section revealed)") {
    // Nil-name expense: latch fires at init, Recents shows immediately.
    let budget = DebugData.dailyDefault()
    let blankExpense = ExpenseItem(amount: 8.00, name: nil, date: Date())
    blankExpense.budget = budget
    return NavigationStack {
      AddEditExpenseView(viewModel: AddEditExpenseViewModel(editing: blankExpense, weekStart: .sunday))
    }
    .modelContainer(PreviewContainer.make())
    .environment(AppSettings())
  }

  #Preview("Recents — xxxLarge Dynamic Type") {
    NavigationStack {
      AddEditExpenseView(viewModel: AddEditExpenseViewModel(adding: DebugData.dailyDefault(), weekStart: .sunday))
    }
    .modelContainer(PreviewContainer.make())
    .environment(AppSettings())
    .dynamicTypeSize(.xxxLarge)
  }
#endif
