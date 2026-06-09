import SwiftUI

// MARK: - Add Funds card (F-6.01)

extension AddEditExpenseView {
  /// The fourth form card — discrete `Toggle` that switches the entry between an expense
  /// (subtracts from remaining) and an add-funds adjustment (adds to remaining). Lives at
  /// the end of the form because the action is intentionally low-frequency; the strong
  /// feedback (title flip, amount tint, description seed) compensates.
  var addFundsCard: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 6) {
        Toggle(isOn: $viewModel.isAddFunds) {
          Text(String(
            localized: "addEditExpense.addFunds.toggle.label",
            defaultValue: "Add funds",
            comment: "Label for the toggle that switches a transaction between expense and add-funds (F-6.01)."
          ))
          .font(.body)
        }
        .tint(.accentColor)
        Text(String(
          localized: "addEditExpense.addFunds.toggle.caption",
          defaultValue: "Adds to your remaining balance instead of subtracting.",
          comment: "Explanatory caption below the Add Funds toggle (F-6.01)"
        ))
        .font(.caption)
        .foregroundStyle(.primary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .backgroundStyle(Color("CellBackground"))
  }
}
