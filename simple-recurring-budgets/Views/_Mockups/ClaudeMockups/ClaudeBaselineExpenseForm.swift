#if DEBUG
  import SwiftUI

  /// Baseline — a faithful, self-contained copy of today's `AddEditExpenseView` (Add mode,
  /// no F-7.04 recents). This is the "copy of that file" reference and the control to
  /// compare the three variations against. Renamed types let it compile alongside the
  /// shipping view in the same DEBUG module.
  struct ClaudeBaselineExpenseForm: View {
    @State private var amount: Decimal?
    @State private var name: String
    @State private var date = Date()
    @State private var isAddFunds = false

    init(initialName: String = "", initialAmount: Decimal? = nil) {
      _name = State(initialValue: initialName)
      _amount = State(initialValue: initialAmount)
    }

    var body: some View {
      ScrollView {
        VStack(spacing: 16) {
          ClaudeAmountCard(amount: $amount, isAddFunds: isAddFunds)
          ClaudeDescriptionCard(name: $name)
          ClaudeWhenCard(date: $date)
          ClaudeAddFundsCard(isAddFunds: $isAddFunds)
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 32)
      }
      .navigationTitle(isAddFunds ? "Add Funds" : "Add Expense")
      .navigationBarTitleDisplayMode(.inline)
      .appBackground()
      .toolbar {
        ClaudeExpenseToolbar(canSave: ClaudeExpenseMock.canSave(amount: amount))
      }
    }
  }

  // MARK: - Previews

  #Preview("Baseline — Light") {
    NavigationStack { ClaudeBaselineExpenseForm() }
      .environment(AppSettings())
  }

  #Preview("Baseline — Dark") {
    NavigationStack { ClaudeBaselineExpenseForm() }
      .environment(AppSettings())
      .preferredColorScheme(.dark)
  }

#endif
