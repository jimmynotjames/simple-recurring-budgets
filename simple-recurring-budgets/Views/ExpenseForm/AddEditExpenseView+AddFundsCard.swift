import SwiftUI

// MARK: - Add Funds card (F-6.01)

extension AddEditExpenseView {
  /// Toggle switching the entry between an expense and an add-funds adjustment. Sits last
  /// because it's low-frequency; the title flip, amount tint, and description seed make
  /// the state obvious.
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
