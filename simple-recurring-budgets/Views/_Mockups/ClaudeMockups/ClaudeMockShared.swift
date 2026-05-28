#if DEBUG
  import SwiftUI

  // MARK: - Overview

  //
  // Workshop mockups for F-7.04 (Recently used expenses) on the Add Expense surface.
  // These are *throwaway design explorations* — self-contained, DEBUG-only, and driven
  // entirely by `#Preview`. They reuse the real form chrome (`CurrencyAmountField`,
  // `appBackground()`, `Color("CellBackground")`, the money colors) so spacing, type, and
  // color read like the shipping `AddEditExpenseView`, but they carry no data layer: the
  // recents are hard-coded samples and Save/Cancel are inert.
  //
  // Type names are `Claude`-prefixed so they coexist with the sibling `_Mockups/AddEditExpense`
  // set without symbol collisions in the same DEBUG module.
  //
  // The folder holds a baseline (current design, no recents) plus two variations:
  //   • ClaudeBaselineExpenseForm — control / "the copy"
  //   • ClaudeMockupQuickPicks     — suggestion-first tile grid above Amount
  //   • ClaudeMockupRecentsPills   — horizontal pill row in its own section box above Amount

  // MARK: - Sample data

  /// One reusable prior entry. F-7.04 reuses *both* name and amount, so a sample carries both.
  struct ClaudeRecentExpense: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let amount: Decimal
  }

  enum ClaudeRecentExpenses {
    /// A daily-food-budget flavored set (the Juliette persona): the kind of repeating
    /// entries that make one-tap reuse worthwhile.
    static let samples: [ClaudeRecentExpense] = [
      ClaudeRecentExpense(name: "Morning coffee", amount: 5.50),
      ClaudeRecentExpense(name: "Lunch", amount: 14.25),
      ClaudeRecentExpense(name: "Groceries", amount: 42.00),
      ClaudeRecentExpense(name: "Smoothie", amount: 8.75),
      ClaudeRecentExpense(name: "Bagel", amount: 3.25),
      ClaudeRecentExpense(name: "Burrito", amount: 11.50),
    ]

    /// A longer set for stress-testing dense layouts. The final entry is deliberately long
    /// so the Quick Picks tile max-width truncation behavior is visible in the canvas.
    static let manySamples: [ClaudeRecentExpense] = samples + [
      ClaudeRecentExpense(name: "Parking", amount: 8.00),
      ClaudeRecentExpense(name: "Pharmacy", amount: 19.40),
      ClaudeRecentExpense(name: "Afternoon coffee", amount: 4.75),
      ClaudeRecentExpense(name: "Saturday brunch with friends", amount: 38.50),
    ]

    /// Keep the surface glanceable rather than a wall of history.
    static let displayLimit = 5

    /// Empty query → all recents (capped). Non-empty → case-insensitive name match.
    /// Models the F-7.04 "suggestion → autocomplete on the same surface" rule: the set
    /// narrows as the user types and yields an empty array (caller hides the surface)
    /// when nothing matches.
    static func filtered(
      query: String,
      from recents: [ClaudeRecentExpense] = samples,
      limit: Int = displayLimit
    ) -> [ClaudeRecentExpense] {
      let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
      let matched = trimmed.isEmpty
        ? recents
        : recents.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
      return Array(matched.prefix(limit))
    }
  }

  enum ClaudeExpenseMock {
    static let currencyCode = "USD"

    static func canSave(amount: Decimal?) -> Bool {
      guard let amount, amount > 0 else { return false }
      return true
    }

    /// F-7.04: a tap fills both draft fields and leaves the user on the sheet to review
    /// and Save — it never logs instantly.
    static func apply(_ suggestion: ClaudeRecentExpense, name: inout String, amount: inout Decimal?) {
      name = suggestion.name
      amount = suggestion.amount
    }
  }

  // MARK: - Shared form chrome

  /// The muted section header used above every form card, matching `AddEditExpenseView`.
  struct ClaudeSectionLabel: View {
    let text: String

    var body: some View {
      Text(text)
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
  }

  /// Amount card — the hero field, auto-focused on open. Mirrors the real `amountCard`.
  ///
  /// `amountFieldRefreshToken` is an opaque value that, when changed by the caller, forces
  /// the inner `CurrencyAmountField` to re-mount via `.id(...)`. This works around the
  /// shipping field's deliberate one-way text→value flow: its internal `text` is seeded
  /// from `value` only on `.onAppear` and never re-seeded, so an external programmatic
  /// write to `amount` (e.g., a F-7.04 "fill from recent" tap) doesn't update the display.
  /// Bumping the token causes SwiftUI to discard and rebuild the field, and the fresh
  /// `.onAppear` then seeds it from the new `value`. The real implementation will need a
  /// proper external-write path on `CurrencyAmountField`; this is the mockup workaround.
  struct ClaudeAmountCard<Footer: View>: View {
    @Binding var amount: Decimal?
    var isAddFunds: Bool = false
    var amountFieldRefreshToken: AnyHashable = 0
    @ViewBuilder var footer: () -> Footer

    @Environment(AppSettings.self) private var settings

    var body: some View {
      GroupBox {
        VStack(alignment: .leading, spacing: 12) {
          CurrencyAmountField(
            value: $amount,
            currencyCode: ClaudeExpenseMock.currencyCode,
            currencyDisplay: settings.currencyDisplay,
            placeholder: "0",
            accessibilityLabel: isAddFunds ? "Funds amount" : "Expense amount",
            autoFocus: true,
            tint: isAddFunds ? Color.moneySurplus : nil
          )
          .id(amountFieldRefreshToken)
          footer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      } label: {
        ClaudeSectionLabel(text: "Amount")
      }
      .backgroundStyle(Color("CellBackground"))
    }
  }

  extension ClaudeAmountCard where Footer == EmptyView {
    init(amount: Binding<Decimal?>, isAddFunds: Bool = false, amountFieldRefreshToken: AnyHashable = 0) {
      self.init(amount: amount, isAddFunds: isAddFunds, amountFieldRefreshToken: amountFieldRefreshToken) {
        EmptyView()
      }
    }
  }

  /// Description card with an optional trailing accessory rendered below the text field.
  /// Variations that thread suggestions through the Description field pass that UI here.
  struct ClaudeDescriptionCard<Accessory: View>: View {
    @Binding var name: String
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
      GroupBox {
        VStack(alignment: .leading, spacing: 10) {
          TextField("e.g. Coffee", text: $name)
            .font(.body)
            .accessibilityLabel("Expense description")
          accessory()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      } label: {
        ClaudeSectionLabel(text: "Description (optional)")
      }
      .backgroundStyle(Color("CellBackground"))
    }
  }

  extension ClaudeDescriptionCard where Accessory == EmptyView {
    init(name: Binding<String>) {
      self.init(name: name) { EmptyView() }
    }
  }

  /// When card — date + time picker. Mirrors the real `whenCard` (bounds omitted; the
  /// mockups don't model a budget lifecycle).
  struct ClaudeWhenCard: View {
    @Binding var date: Date

    var body: some View {
      GroupBox {
        DatePicker(selection: $date, displayedComponents: [.date, .hourAndMinute]) {
          EmptyView()
        }
        .datePickerStyle(.compact)
        .labelsHidden()
        .accessibilityLabel("When")
        .frame(maxWidth: .infinity, alignment: .leading)
      } label: {
        ClaudeSectionLabel(text: "When")
      }
      .backgroundStyle(Color("CellBackground"))
    }
  }

  /// Add Funds card (F-6.01) — kept so the mockups show the full form height.
  struct ClaudeAddFundsCard: View {
    @Binding var isAddFunds: Bool

    var body: some View {
      GroupBox {
        VStack(alignment: .leading, spacing: 6) {
          Toggle(isOn: $isAddFunds) {
            Text(verbatim: "Add funds").font(.body)
          }
          .tint(.accentColor)
          Text(verbatim: "Adds to your remaining balance instead of subtracting.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .backgroundStyle(Color("CellBackground"))
    }
  }

  struct ClaudeExpenseToolbar: ToolbarContent {
    let canSave: Bool

    var body: some ToolbarContent {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") {}
      }
      ToolbarItem(placement: .confirmationAction) {
        Button("Save") {}
          .disabled(!canSave)
          .fontWeight(.semibold)
          .tint(.accentColor)
      }
    }
  }

  extension Decimal {
    /// Currency string in the mockup's fixed currency, honoring the user's display preference.
    func claudeFormatted(display: CurrencyDisplayPreference) -> String {
      formatted(currencyCode: ClaudeExpenseMock.currencyCode, display: display)
    }
  }

#endif
