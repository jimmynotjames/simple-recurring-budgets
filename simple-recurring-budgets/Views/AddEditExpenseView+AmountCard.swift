import SwiftUI

// MARK: - Amount card

extension AddEditExpenseView {
  var amountCard: some View {
    GroupBox {
      CurrencyAmountField(
        value: $viewModel.amount,
        currencyCode: viewModel.currencyCode,
        currencyDisplay: settings.currencyDisplay,
        placeholder: String(
          localized: "addEditExpense.field.amount.placeholder",
          defaultValue: "0",
          comment: "Placeholder in the expense amount field when no value is entered"
        ),
        accessibilityLabel: viewModel.isAddFunds
          ? String(
            localized: "addEditExpense.field.amount.accessibilityLabel.addFunds",
            defaultValue: "Funds amount",
            comment: "VoiceOver label for the amount field when Add Funds is toggled on (F-6.01)"
          )
          : String(
            localized: "addEditExpense.field.amount.accessibilityLabel",
            defaultValue: "Expense amount",
            comment: "VoiceOver label for the expense amount field"
          ),
        autoFocus: !viewModel.isEditing,
        tint: viewModel.isAddFunds ? Color.moneySurplus : nil
      )
    } label: {
      sectionLabel(String(
        localized: "addEditExpense.section.amount",
        defaultValue: "Amount",
        comment: "Section header above the expense amount field"
      ))
    }
    .backgroundStyle(Color("CellBackground"))
  }
}
