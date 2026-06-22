import SwiftData
import SwiftUI

// MARK: - Suggestion value type

/// Condensed view of a prior `ExpenseItem` for use as an F-7.04 Recents suggestion.
/// Identity is the source expense's `persistentModelID` so duplicate name + amount
/// pairs from repeated entries remain distinct rows under SwiftUI identity-based diffing.
struct RecentExpenseSuggestion: Identifiable, Hashable {
  let id: PersistentIdentifier
  let name: String
  let amount: Decimal
}

// MARK: - ViewModel: candidate set, filter, and apply

extension AddEditExpenseViewModel {
  /// How many tiles the row *displays* at once — both before filtering (Cap A) and
  /// after the typed query filters the corpus (Cap B). Distinct from
  /// `recentsCorpusLimit`: the filter searches the full memoized corpus, then this cap
  /// trims what's rendered. Sized to give less-frequent picks a fighting chance on
  /// dense budgets — a user who logs three times a day but also gets a croissant every
  /// Monday should still see the croissant.
  static let recentsDisplayLimit: Int = 30

  /// How many candidate tiles the memoized *search corpus* holds (Cap C). Typing in the
  /// Description field filters this full set — not the displayed row — so a name beyond
  /// the visible tiles still surfaces once a query narrows the matches. The cap exists
  /// purely to bound the sheet-open memoization and the per-keystroke O(C) substring
  /// filter on pathological budgets; ~200 unique names covers a year+ of realistic
  /// per-category logging.
  static let recentsCorpusLimit: Int = 200

  /// How many times an exact (name, amount) pair must recur before it earns an *extra*
  /// variant tile beyond its name's base tile. Gates out coincidental repeats (two
  /// round-number "Lunch $20" months apart) while true fixtures — a small and a large
  /// coffee at stable prices — qualify within a couple of weeks. The base most-recent
  /// amount per name always shows regardless of count.
  static let variantRecurrenceThreshold: Int = 3

  /// Maximum *extra* variant tiles per name beyond the base tile (so max 3 tiles share
  /// one name). Keeps a single multi-price fixture from crowding other names out of
  /// the row.
  static let maxVariantsPerName: Int = 2

  /// Compute the recents candidate corpus from a budget's expense history. Pure function;
  /// called from `AddEditExpenseViewModel.init` to populate `cachedRecentCandidates`.
  ///
  /// **Algorithm: pair-aggregate, then group, then flatten.**
  /// - **Pass 1 (O(N)):** aggregate expenses into (folded name, amount) pairs, tracking
  ///   each pair's occurrence count and most-recent occurrence. Names fold for case AND
  ///   diacritic insensitivity so "Café" / "cafe" / "CAFÉ" collapse — the same
  ///   equivalence class the typed-query filter (`range(of:options:)`) considers equal.
  /// - **Pass 2:** per name, the most-recent pair becomes the **base tile** (preserving
  ///   the original "most recent amount wins" behavior as the floor); other pairs
  ///   qualify as **variant tiles** only when their count meets
  ///   `variantRecurrenceThreshold`, capped at `maxVariantsPerName`. The recurrence gate
  ///   is what separates a real two-price fixture (small/large coffee) from one-off
  ///   price jitter (groceries at $87.32 / $91.10 / $103.55 → one tile, not three).
  /// - **Pass 3:** name groups sort by their most-recent date descending and flatten —
  ///   base first, variants clustered immediately after, so duplicate names read as one
  ///   family — then `prefix(recentsCorpusLimit)`.
  ///
  /// **F-7.04 exclusions (unchanged):**
  /// - **Excludes Add Funds entries (F-6.01)** — surplus-direction rows don't reuse
  ///   meaningfully as expense suggestions.
  /// - **Excludes unnamed entries** — "Untitled $7.50" isn't actionable as a suggestion,
  ///   and description-optional quick logging would otherwise flood the row with bare
  ///   amounts.
  static func computeRecentCandidates(
    for budget: Budget?,
    limit: Int = recentsCorpusLimit
  ) -> [RecentExpenseSuggestion] {
    guard let budget else { return [] }
    // Per-(name, amount) aggregate: the most recent source occurrence (whose model ID
    // becomes the tile identity and whose trimmed name is the one displayed) plus the
    // pair's total occurrence count for the recurrence gate.
    struct PairAggregate {
      var item: ExpenseItem
      var displayName: String
      var count: Int
    }
    // Pass 1 (O(N)): aggregate by folded name, then by exact amount within the name.
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
    // Pass 2: per name, base tile (most recent pair) + recurrence-gated variants.
    var groups: [[PairAggregate]] = []
    for pairs in byName.values {
      let sorted = pairs.values.sorted { $0.item.date > $1.item.date }
      guard let base = sorted.first else { continue }
      let variants = sorted.dropFirst()
        .filter { $0.count >= Self.variantRecurrenceThreshold }
        .prefix(Self.maxVariantsPerName)
      groups.append([base] + variants)
    }
    // Pass 3: order groups by recency (a group's first tile is its most recent pair),
    // flatten so variants cluster after their base, cap the corpus.
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

  /// Fold a string for case- and diacritic-insensitive comparison. "Café" → "cafe", etc.
  /// Used as the dedup key in `computeRecentCandidates` to keep the equivalence class
  /// aligned with the filter's `[.caseInsensitive, .diacriticInsensitive]` substring match.
  fileprivate static func foldedKey(_ string: String) -> String {
    string.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
  }

  /// True when any prior expenses on this budget could surface as suggestions. Drives the
  /// section's *true-empty* visibility (per F-7.04 edge case "presumably the surface
  /// doesn't render"). Distinct from `filteredRecentSuggestions.isEmpty`, which is the
  /// *filter-empty* state and renders the soft "No matches" placeholder instead.
  var hasRecentSources: Bool {
    !cachedRecentCandidates.isEmpty
  }

  /// The tiles to render, filtered against the current typed query and capped for
  /// display. Empty query → the corpus's first `recentsDisplayLimit` tiles (Cap A);
  /// non-empty query → case- AND diacritic-insensitive substring match against name (so
  /// typing "cafe" finds a "Café" recent) across the **full** memoized corpus — not just
  /// the unfiltered row — then the same display cap (Cap B). The match equivalence is
  /// the same folding used to group the corpus; see `foldedKey(_:)`. Filter cost is
  /// O(C) per keystroke with C ≤ `recentsCorpusLimit`.
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

  /// True when the Recents section should appear:
  /// - **Add mode:** whenever the budget has at least one candidate (unchanged).
  /// - **Edit/View mode:** once the `recentsRevealedInEdit` latch has been set — i.e. after
  ///   the Description was blank at sheet-open or the user cleared it mid-session. Once
  ///   revealed the section persists for the sheet's lifetime regardless of whether the
  ///   Description becomes non-empty again (e.g. after a tile tap or re-type). This is
  ///   the blank-Description-gated reveal from F-7.04 (changed from Add-only).
  var shouldShowRecentsSection: Bool {
    hasRecentSources && (!isEditing || recentsRevealedInEdit)
  }

  /// F-7.04: apply a tapped Recents suggestion to the draft. Always writes `name` and
  /// resets the Add Funds toggle to off — a Recents tile represents a prior expense,
  /// so the toggle is reset to match that semantic; otherwise a user who toggled Add
  /// Funds on (and abandoned the action) could silently log the recent's amount as an
  /// add-funds adjustment.
  ///
  /// **Smart-apply provenance rule for `amount`:** the tile's amount is written only
  /// when the draft amount is `.empty` or `.tileSeeded` (a previous tile's seed being
  /// replaced by suggestion-switching). A `.userTyped` amount survives the tap — with
  /// the section rendered as the Description field's autocomplete, the tap reads as
  /// "complete the description," and completing one field must not silently destroy a
  /// sibling the user just filled (the unnoticed-overwrite → wrong saved amount is the
  /// costly failure mode; the reverse is visible and fixable in place). Escape hatch
  /// when the user *does* want the tile's amount over their own: clear (✕) then re-tap.
  ///
  /// The date stays today/clamped per F-2.04, and Save is not triggered — the user
  /// reviews then confirms.
  ///
  /// Emits an `expense_recent_reused` analytics event with strictly categorical, bucketed
  /// properties (no PII per analytics-spec.md §2.1): the budget's period, the number of
  /// tiles visible at tap time, the tile's position, and the length of the typed query
  /// at the moment of the tap (captured before `name` is overwritten).
  ///
  /// The external write to `amount` propagates back into `CurrencyAmountField`'s display
  /// via its bidirectional `lastSyncedValue` sentinel — see the field's docstring for the
  /// disambiguation rule. There is intentionally no convenience overload that defaults
  /// the analytics client: every call site (production tap + tests) passes one explicitly
  /// so the emitted bucket values are always derived from the call's real context.
  func applyRecent(
    _ suggestion: RecentExpenseSuggestion,
    visibleCount: Int,
    tapPosition: Int,
    analytics: any AnalyticsClient
  ) {
    // Capture the typed query length *before* overwriting `name`; the analytic semantic
    // is "what was the user typing when they decided to tap?"
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

  /// F-7.04 double-tap full replace: writes `name` AND `amount` unconditionally,
  /// overriding the provenance rule — the explicit second tap is the user saying
  /// "no, really, all of it." Also resets Add Funds, same as `applyRecent`.
  ///
  /// No analytics here: the double-tap's first tap already ran `applyRecent` and
  /// emitted `expense_recent_reused` (the tile's tap gesture fires simultaneously with
  /// the button action, not instead of it), so tracking again would double-count the
  /// reuse. A dedicated full-replace property is deferred to the formalization pass.
  func applyRecentFullReplace(_ suggestion: RecentExpenseSuggestion) {
    isAddFunds = false
    name = suggestion.name
    seedAmount(from: suggestion)
  }

  /// Write a suggestion's amount into the draft as a tile seed: the observer-suppression
  /// flag keeps `amount`'s `didSet` from classifying the write as user typing, and the
  /// resulting `.tileSeeded` provenance lets a later tile tap replace it.
  private func seedAmount(from suggestion: RecentExpenseSuggestion) {
    isSeedingAmountFromSuggestion = true
    amount = suggestion.amount
    amountProvenance = .tileSeeded
    isSeedingAmountFromSuggestion = false
  }
}

// MARK: - View entry point

extension AddEditExpenseView {
  /// F-7.04 Recents section. Renders below the Description card when the budget has prior
  /// expense candidates and the section should be visible per `shouldShowRecentsSection`.
  ///
  /// **Add mode:** always visible when candidates exist.
  /// **Edit/View mode:** revealed once the Description has been blank (on open or cleared
  /// mid-session), then persists for the sheet's lifetime. The latch and the tap semantics
  /// are described in `shouldShowRecentsSection` and `applyRecent` respectively.
  ///
  /// Placement is deliberate: the Description field doubles as the tiles' filter query, so
  /// the suggestions sit directly beneath their input (autocomplete idiom), while the Amount
  /// card keeps the top slot for the amount-first quick-log flow.
  ///
  /// **Empty-state policy (two cases):**
  /// - *True-empty* (`hasRecentSources == false`) — the whole section is gone so the
  ///   form opens calmly. The feature self-discovers after the user's first Save.
  /// - *Filter-empty* (sources non-empty, query has no matches) — the card stays mounted
  ///   with a quiet "No matches" placeholder so the form below doesn't shift while the
  ///   user types.
  @ViewBuilder
  var recentsSection: some View {
    if viewModel.shouldShowRecentsSection {
      RecentsSectionView(viewModel: viewModel)
    }
  }
}

// MARK: - RecentsSectionView

/// Inner view that renders the Recents card and owns the `@ScaledMetric` geometry. Kept
/// as a struct (not an extension method on `AddEditExpenseView`) because extensions can't
/// declare stored properties and `@ScaledMetric` requires storage to participate in the
/// SwiftUI environment-driven type-size invalidation pipeline.
private struct RecentsSectionView: View {
  let viewModel: AddEditExpenseViewModel

  @Environment(AppSettings.self) private var settings
  @Environment(\.analytics) private var analytics

  /// Tile geometry scales with Dynamic Type so the section remains legible at larger
  /// type sizes; the base values match the workshop-tuned constants.
  @ScaledMetric(relativeTo: .subheadline) private var tileMaxWidth: CGFloat = 180
  @ScaledMetric(relativeTo: .subheadline) private var tilePaddingHorizontal: CGFloat = 14
  @ScaledMetric(relativeTo: .subheadline) private var tilePaddingVertical: CGFloat = 11

  var body: some View {
    // Compute the filtered set once per body render. Used in three places (the empty
    // gate, the header's overflow-hint threshold, and the tile row's enumeration);
    // re-accessing the VM property each time would re-filter on every call.
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
      // Swipe-for-more icon shows only when content actually overflows the visible row.
      // Threshold is intentionally loose; precise overflow detection isn't worth the cost.
      // Decorative — VoiceOver's natural scroll-container behavior reproduces the meaning.
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

  /// One Recents tile. Intrinsic-width with a `tileMaxWidth` cap so short names produce
  /// compact tiles and long ones truncate rather than dominating the row. Hierarchy is
  /// carried by color (primary name vs. secondary amount), not by weight.
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
    // Double-tap = full replace, overriding the amount-provenance rule. Deliberately
    // `simultaneousGesture`, not a counted `onTapGesture` pair: a recognized-together
    // gesture keeps single taps instant (no ~0.3s wait-for-second-tap delay), at the
    // cost that a double-tap's first tap runs the normal smart apply before the second
    // tap upgrades it — which converges to the same full-replace end state.
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
    // VoiceOver parallel for the sighted double-tap (VO's own double-tap is activation).
    .accessibilityAction(named: String(
      localized: "addEditExpense.recents.tile.accessibilityAction.fullReplace",
      defaultValue: "Replace amount and description",
      comment: "VoiceOver custom action name on an F-7.04 Recents tile; mirrors the sighted double-tap that overwrites both fields even when the user already typed an amount."
    )) {
      viewModel.applyRecentFullReplace(suggestion)
    }
  }

  /// Reserves the tile row's height with a quiet "No matches" label so the form below
  /// stays put while the user types away every match. The phantom content mirrors a real
  /// tile's two-line subheadline geometry, so no magic constant drifts if tile metrics
  /// change. Kept structurally adjacent to `tile(for:position:visibleCount:)` — update
  /// both together.
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
    // Expected tiles: TWO "Coffee" tiles clustered together (4.50 base + 5.75 variant,
    // both recurring ≥ variantRecurrenceThreshold times) and ONE "Groceries" tile
    // (three one-off jittered amounts collapse to the most recent).
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
