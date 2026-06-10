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
  /// How many recents to surface at once (after dedup). Sized to give less-frequent picks
  /// a fighting chance on dense budgets — a user who logs three times a day but also gets
  /// a croissant every Monday should still see the croissant.
  static let recentsDisplayLimit: Int = 15

  /// Compute the recents candidate set from a budget's expense history. Pure function;
  /// called from `AddEditExpenseViewModel.init` to populate `cachedRecentCandidates`.
  ///
  /// **Algorithm: hash-then-sort.** One O(N) scan into a dict keyed by lowercased name,
  /// keeping the most recent occurrence per unique name, then an O(M log M) sort of the
  /// M unique entries by date descending, then `prefix(limit)`. For heavy-duplicate
  /// budgets (M << N), this is much faster than sort-then-dedup, which would touch all
  /// N entries up front. Worst case (every entry unique → M = N) it's O(N log N), no
  /// worse than the naive approach.
  ///
  /// **F-7.04 workshop defaults:**
  /// - **Ranking:** recency-driven, descending. Duplicates by description (case-
  ///   insensitive) collapse to the most recent occurrence, whose amount is the one
  ///   surfaced.
  /// - **Excludes Add Funds entries (F-6.01)** — surplus-direction rows don't reuse
  ///   meaningfully as expense suggestions.
  /// - **Excludes unnamed entries** — "Untitled $7.50" isn't actionable as a suggestion.
  static func computeRecentCandidates(
    for budget: Budget?,
    limit: Int = recentsDisplayLimit
  ) -> [RecentExpenseSuggestion] {
    guard let budget else { return [] }
    // Pass 1 (O(N)): collapse to most-recent per unique name. The dict stores both the
    // source ExpenseItem and its trimmed display name so Pass 2 doesn't re-trim.
    var byKey: [String: (item: ExpenseItem, displayName: String)] = [:]
    for expense in budget.expenseItems {
      guard !expense.isAddFunds else { continue }
      let trimmed = (expense.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { continue }
      // Fold the dedup key for case AND diacritic insensitivity so "Café" / "cafe" /
      // "CAFÉ" all collapse — and so the dedup equivalence class matches what the
      // filter (`range(of:options:)` below) considers equal.
      let key = foldedKey(trimmed)
      if let existing = byKey[key], existing.item.date >= expense.date {
        continue // existing is at least as recent — keep it
      }
      byKey[key] = (expense, trimmed)
    }
    // Pass 2 (O(M log M)): sort unique entries by recency, take top K.
    return byKey.values
      .sorted { $0.item.date > $1.item.date }
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

  /// Candidates filtered against the current typed query. Empty query → all candidates;
  /// non-empty query → case- AND diacritic-insensitive substring match against name (so
  /// typing "cafe" finds a "Café" recent). The same equivalence is used to dedup the
  /// candidate set; see `foldedKey(_:)`. Filter cost is O(K) — the candidate set is
  /// already memoized and capped at `recentsDisplayLimit`.
  var filteredRecentSuggestions: [RecentExpenseSuggestion] {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return cachedRecentCandidates }
    return cachedRecentCandidates.filter {
      $0.name.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
  }

  /// True only when the Recents section should appear: Add mode with at least one
  /// candidate. Edit mode never shows Recents (F-7.04 is an Add-only affordance).
  var shouldShowRecentsSection: Bool {
    !isEditing && hasRecentSources
  }

  /// F-7.04: apply a tapped Recents suggestion to the draft. Writes both `name` and
  /// `amount` AND resets the Add Funds toggle to off — a Recents tile represents a
  /// prior expense, so the toggle is reset to match that semantic. Otherwise a user
  /// who toggled Add Funds on (and abandoned the action) could silently log the
  /// recent's amount as an add-funds adjustment. The date stays today/clamped per
  /// F-2.04, and Save is not triggered — the user reviews then confirms.
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
    amount = suggestion.amount

    let period = budget?.periodEnum ?? .daily
    analytics.track(
      AnalyticsEvent.expenseRecentReused,
      properties: [
        AnalyticsProperty.period: period.analyticsValue,
        AnalyticsProperty.recentsVisibleCount: recentsVisibleCountBucket(visibleCount),
        AnalyticsProperty.recentsTapPosition: recentsTapPositionBucket(tapPosition),
        AnalyticsProperty.nameQueryLength: nameQueryLengthBucket(queryLengthAtTap),
      ]
    )
  }
}

// MARK: - View entry point

extension AddEditExpenseView {
  /// F-7.04 Recents section. Renders above the Amount card in Add mode when the budget
  /// has prior expense candidates; hidden entirely otherwise.
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
      AddEditExpenseView(viewModel: AddEditExpenseViewModel(adding: DebugData.dailyDefault()))
    }
    .modelContainer(PreviewContainer.make())
    .environment(AppSettings())
  }

  #Preview("Recents — Dark") {
    NavigationStack {
      AddEditExpenseView(viewModel: AddEditExpenseViewModel(adding: DebugData.dailyDefault()))
    }
    .modelContainer(PreviewContainer.make())
    .environment(AppSettings())
    .preferredColorScheme(.dark)
  }

  #Preview("Recents — Empty: no prior expenses") {
    let budget = Budget(name: "Daily — fresh", currencyCode: "USD", period: .daily)
    budget.startDate = Calendar.current.startOfDay(for: Date())
    return NavigationStack {
      AddEditExpenseView(viewModel: AddEditExpenseViewModel(adding: budget))
    }
    .modelContainer(PreviewContainer.make())
    .environment(AppSettings())
  }

  #Preview("Recents — Empty: no filter matches") {
    let budget = DebugData.dailyDefault()
    let vm = AddEditExpenseViewModel(adding: budget)
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
      AddEditExpenseView(viewModel: AddEditExpenseViewModel(adding: budget))
    }
    .modelContainer(PreviewContainer.make())
    .environment(AppSettings())
  }

  #Preview("Recents — Edit mode (no section)") {
    let budget = DebugData.dailyDefault()
    return NavigationStack {
      AddEditExpenseView(viewModel: AddEditExpenseViewModel(editing: budget.expenseItems[0]))
    }
    .modelContainer(PreviewContainer.make())
    .environment(AppSettings())
  }

  #Preview("Recents — xxxLarge Dynamic Type") {
    NavigationStack {
      AddEditExpenseView(viewModel: AddEditExpenseViewModel(adding: DebugData.dailyDefault()))
    }
    .modelContainer(PreviewContainer.make())
    .environment(AppSettings())
    .dynamicTypeSize(.xxxLarge)
  }
#endif
