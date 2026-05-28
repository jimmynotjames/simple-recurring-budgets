#if DEBUG
  import SwiftUI

  /// Variation 2 — pill row (UNIQUE direction).
  ///
  /// A dedicated section box at the **top** of the form holds a single horizontal row of
  /// description-leading pills ("Coffee · $5.50"), following the accounting-ledger reading
  /// order — thing first, amount second — that the UX brief calls out. Recognition tasks
  /// favor the most semantically distinctive token first, and names disambiguate faster
  /// than dollar amounts when scanning a few recents. One tap fills both fields; the user
  /// then lands on the Amount card to confirm.
  ///
  /// Typing into Description still filters the pills (F-7.04 "same surface"); the section
  /// hides entirely when nothing matches.
  struct ClaudeMockupRecentsPills: View {
    @State private var amount: Decimal?
    @State private var name: String
    @State private var date = Date()
    @State private var isAddFunds = false
    /// Bumped after a recents tap to force `CurrencyAmountField` to re-seed (see
    /// `ClaudeAmountCard` docs).
    @State private var amountFieldRefresh = 0

    @Environment(AppSettings.self) private var settings

    private let sourceRecents: [ClaudeRecentExpense]

    init(
      initialName: String = "",
      initialAmount: Decimal? = nil,
      recents: [ClaudeRecentExpense] = ClaudeRecentExpenses.samples
    ) {
      _name = State(initialValue: initialName)
      _amount = State(initialValue: initialAmount)
      sourceRecents = recents
    }

    private var recents: [ClaudeRecentExpense] {
      ClaudeRecentExpenses.filtered(query: name, from: sourceRecents)
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
            pillsCard
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

    private var pillsCard: some View {
      GroupBox {
        if recents.isEmpty {
          noMatchesPlaceholder
        } else {
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
              ForEach(recents) { recent in
                pill(for: recent)
              }
            }
            .padding(.vertical, 2) // breathing room for the pill edges
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      } label: {
        ClaudeSectionLabel(text: "Recents")
      }
      .backgroundStyle(Color("CellBackground"))
    }

    /// Reserves the pill row's height with a quiet "No matches" label so the form below
    /// stays put while the user types away every match. A hidden pill anchors the height
    /// exactly — no magic constant to drift if pill metrics change later.
    private var noMatchesPlaceholder: some View {
      ZStack(alignment: .leading) {
        pill(for: ClaudeRecentExpense(name: " ", amount: 0))
          .hidden()
          .accessibilityHidden(true)
        // Mockup-only literal — Text(verbatim:) keeps it out of the localization catalog.
        Text(verbatim: "No matches")
          .font(.subheadline)
          .foregroundStyle(.tertiary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pill(for recent: ClaudeRecentExpense) -> some View {
      Button {
        ClaudeExpenseMock.apply(recent, name: &name, amount: &amount)
        amountFieldRefresh += 1
      } label: {
        HStack(spacing: 6) {
          Text(recent.name).lineLimit(1)
          // Bullet at `.secondary` reads as a clear separator without competing with the
          // primary text — heavier than the typographic middle-dot at `.tertiary`.
          Text(verbatim: "•").foregroundStyle(.secondary)
          Text(recent.amount.claudeFormatted(display: settings.currencyDisplay))
            .monospacedDigit()
        }
        .font(.subheadline)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(Color.secondary.opacity(0.12)))
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Use \(recent.name), \(recent.amount.claudeFormatted(display: settings.currencyDisplay))")
    }
  }

  // MARK: - Previews

  #Preview("Recents pills — Light") {
    NavigationStack { ClaudeMockupRecentsPills() }
      .environment(AppSettings())
  }

  #Preview("Recents pills — Dark") {
    NavigationStack { ClaudeMockupRecentsPills() }
      .environment(AppSettings())
      .preferredColorScheme(.dark)
  }

  #Preview("Recents pills — Filtering") {
    NavigationStack { ClaudeMockupRecentsPills(initialName: "co") }
      .environment(AppSettings())
  }

  #Preview("Recents pills — Filled") {
    NavigationStack { ClaudeMockupRecentsPills(initialName: "Smoothie", initialAmount: 8.75) }
      .environment(AppSettings())
  }

  // Empty-state previews — both cases should render as the plain form with no Recents section.

  #Preview("Recents pills — Empty: no prior expenses") {
    NavigationStack { ClaudeMockupRecentsPills(recents: []) }
      .environment(AppSettings())
  }

  #Preview("Recents pills — Empty: no filter matches") {
    NavigationStack { ClaudeMockupRecentsPills(initialName: "Pizza") }
      .environment(AppSettings())
  }

#endif
