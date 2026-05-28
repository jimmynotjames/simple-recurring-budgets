#if DEBUG
  import SwiftUI

  /// Variation 1 — Quick Picks tile row (UNIQUE direction).
  ///
  /// A dedicated section box at the **top** of the form holds a single horizontal row of
  /// two-line tappable tiles (name above, amount below). Suggestion-first: opening the
  /// sheet immediately offers the user's habitual entries; one tap fills name + amount
  /// and leaves the Save button hot — the shortest path for the recurring, daily-logging
  /// use case the UX brief calls the signature element.
  ///
  /// Layout note: the row uses horizontal scrolling so its height stays **constant**
  /// regardless of how many tiles match. Filtering and tap-to-fill change the row's
  /// contents without shifting anything below, which keeps the form still while the user
  /// is reading and typing. Workshopping established that vertical layout-shift under the
  /// cursor was the dominant UX problem with a cap-and-collapse grid; a horizontal row
  /// satisfies F-7.04's "filter on the same surface" requirement without paying that cost.
  ///
  /// The whole section hides when nothing matches (per F-7.04 "dismisses when there are
  /// no matches"); that's the only vertical shift, and it's discrete rather than
  /// continuous.
  struct ClaudeMockupQuickPicks: View {
    @State private var amount: Decimal?
    @State private var name: String
    @State private var date = Date()
    @State private var isAddFunds = false
    /// Bumped after a recents tap to force `CurrencyAmountField` to re-seed (see
    /// `ClaudeAmountCard` docs).
    @State private var amountFieldRefresh = 0

    @Environment(AppSettings.self) private var settings

    private let sourceRecents: [ClaudeRecentExpense]
    private let limit: Int

    init(
      initialName: String = "",
      initialAmount: Decimal? = nil,
      recents: [ClaudeRecentExpense] = ClaudeRecentExpenses.samples,
      limit: Int = ClaudeRecentExpenses.displayLimit
    ) {
      _name = State(initialValue: initialName)
      _amount = State(initialValue: initialAmount)
      sourceRecents = recents
      self.limit = limit
    }

    private var recents: [ClaudeRecentExpense] {
      ClaudeRecentExpenses.filtered(query: name, from: sourceRecents, limit: limit)
    }

    var body: some View {
      ScrollView {
        VStack(spacing: 16) {
          // Empty-state policy (two cases):
          //   • True-empty (`sourceRecents.isEmpty`, brand-new budget) — hide the section
          //     entirely so the form opens calmly. The feature self-discovers after the
          //     user's first Save (F-7.04 edge case "presumably the surface doesn't render").
          //   • Filter-empty (`sourceRecents` non-empty, query has no matches) — keep the
          //     section mounted with a soft placeholder. F-7.04 says the surface "dismisses
          //     when there are no matches"; once the user is typing, we interpret
          //     "dismisses" as the contents going quiet rather than the whole card
          //     collapsing — discrete vertical jumps under the cursor are jarring and move
          //     tap targets below mid-keystroke.
          if !sourceRecents.isEmpty {
            quickPicksCard
          }
          ClaudeAmountCard(amount: $amount, isAddFunds: isAddFunds, amountFieldRefreshToken: amountFieldRefresh)
          ClaudeDescriptionCard(name: $name)
          ClaudeWhenCard(date: $date)
          ClaudeAddFundsCard(isAddFunds: $isAddFunds)
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 32)
        .animation(.snappy(duration: 0.2), value: recents)
      }
      .navigationTitle(isAddFunds ? "Add Funds" : "Add Expense")
      .navigationBarTitleDisplayMode(.inline)
      .appBackground()
      .toolbar {
        ClaudeExpenseToolbar(canSave: ClaudeExpenseMock.canSave(amount: amount))
      }
    }

    private var quickPicksCard: some View {
      GroupBox {
        if recents.isEmpty {
          noMatchesPlaceholder
        } else {
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
              ForEach(recents) { tile(for: $0) }
            }
            .padding(.bottom, 2) // breathing room below the tile row
          }
        }
      } label: {
        header
      }
      .backgroundStyle(Color("CellBackground"))
    }

    /// Reserves the tile row's height with a quiet "No matches" label so the form below
    /// stays put while the user types away every match. A hidden tile anchors the height
    /// exactly — no magic constant to drift if tile metrics change later.
    private var noMatchesPlaceholder: some View {
      ZStack(alignment: .leading) {
        tile(for: ClaudeRecentExpense(name: " ", amount: 0))
          .hidden()
          .accessibilityHidden(true)
        // Mockup-only literal — Text(verbatim:) keeps it out of the localization catalog.
        Text(verbatim: "No matches")
          .font(.subheadline)
          .foregroundStyle(.tertiary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
      HStack(spacing: 8) {
        Text(verbatim: "Recents")
        Spacer(minLength: 8)
        if recents.count > 3 {
          Image(systemName: "arrow.right")
            .font(.caption)
            .accessibilityLabel("Swipe for more")
        }
      }
      .font(.subheadline)
      .foregroundStyle(.secondary)
    }

    /// Tiles size to their content (intrinsic width) and cap at `tileMaxWidth`. Short names
    /// produce compact tiles; names that don't fit truncate with an ellipsis. The hierarchy
    /// inside the tile is carried purely by **color** (primary name vs. secondary amount) —
    /// not size or weight. Both lines are `.subheadline` regular, so the amount reads at a
    /// glance during review without the name visually shouting.
    private func tile(for recent: ClaudeRecentExpense) -> some View {
      Button {
        ClaudeExpenseMock.apply(recent, name: &name, amount: &amount)
        amountFieldRefresh += 1
      } label: {
        VStack(alignment: .leading, spacing: 4) {
          Text(recent.name)
            .font(.subheadline)
            .foregroundStyle(.primary)
            .lineLimit(1)
          Text(recent.amount.claudeFormatted(display: settings.currencyDisplay))
            .font(.subheadline)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .frame(maxWidth: Self.tileMaxWidth, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        // Neutral fill (not accent-tinted): the rounded-rect chip shape already signals
        // "tappable," and the UX brief reserves muted accents for primary actions like
        // Save. Same `secondary.opacity(0.12)` formula as the Recents Pills capsules, so
        // the two variations rhyme.
        .background(
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.secondary.opacity(0.12))
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Use \(recent.name), \(recent.amount.claudeFormatted(display: settings.currencyDisplay))")
      .accessibilityHint("Fills the amount and description so you can review and save.")
    }

    /// Upper bound on tile width. Sized so realistic recent-name lengths (~22 chars at
    /// `.subheadline.medium`) fit without truncation, but a runaway long name doesn't take
    /// over the whole row.
    private static let tileMaxWidth: CGFloat = 180
  }

  // MARK: - Previews

  // Default previews use the 9-item set so the horizontal-scroll affordance is visible.

  #Preview("Quick picks — Light") {
    NavigationStack {
      ClaudeMockupQuickPicks(recents: ClaudeRecentExpenses.manySamples, limit: 10)
    }
    .environment(AppSettings())
  }

  #Preview("Quick picks — Dark") {
    NavigationStack {
      ClaudeMockupQuickPicks(recents: ClaudeRecentExpenses.manySamples, limit: 10)
    }
    .environment(AppSettings())
    .preferredColorScheme(.dark)
  }

  #Preview("Quick picks — Filtering") {
    NavigationStack {
      ClaudeMockupQuickPicks(
        initialName: "co",
        recents: ClaudeRecentExpenses.manySamples,
        limit: 10
      )
    }
    .environment(AppSettings())
  }

  #Preview("Quick picks — Filled") {
    NavigationStack {
      ClaudeMockupQuickPicks(
        initialName: "Lunch",
        initialAmount: 14.25,
        recents: ClaudeRecentExpenses.manySamples,
        limit: 10
      )
    }
    .environment(AppSettings())
  }

  // Empty-state previews — both cases should render as the plain form with no Recents section.

  #Preview("Quick picks — Empty: no prior expenses") {
    NavigationStack {
      ClaudeMockupQuickPicks(recents: [])
    }
    .environment(AppSettings())
  }

  #Preview("Quick picks — Empty: no filter matches") {
    NavigationStack {
      ClaudeMockupQuickPicks(
        initialName: "Pizza",
        recents: ClaudeRecentExpenses.manySamples,
        limit: 10
      )
    }
    .environment(AppSettings())
  }

#endif
