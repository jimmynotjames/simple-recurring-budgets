import SwiftUI

// MARK: - Amount card

extension AddEditExpenseView {
  var amountCard: some View {
    GroupBox {
      HStack(alignment: .firstTextBaseline, spacing: 2) {
        amountAffix(currencyAffixes.leading)
        DecimalInputField(
          placeholder: String(
            localized: "addEditExpense.field.amount.placeholder",
            defaultValue: "0",
            comment: "Placeholder in the expense amount field when no value is entered"
          ),
          text: $amountText,
          currencyCode: viewModel.currencyCode,
          autoFocus: !viewModel.isEditing,
          textColor: viewModel.isAddFunds ? Color.moneySurplus : .primary,
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
            )
        )
        .frame(maxWidth: .infinity)
        .onChange(of: amountText) { _, newValue in
          viewModel.amount = (try? amountConverter.parseStrategy.parse(newValue))
        }
        amountAffix(currencyAffixes.trailing)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    } label: {
      sectionLabel(String(
        localized: "addEditExpense.section.amount",
        defaultValue: "Amount",
        comment: "Section header above the expense amount field"
      ))
    }
    .backgroundStyle(Color("CellBackground"))
  }

  /// Leading/trailing currency decoration whose side follows the locale's currency convention
  /// (see `CurrencyDisplayPreference.affixes(for:locale:)`), so the editor matches the display path.
  private var currencyAffixes: (leading: String, trailing: String) {
    settings.currencyDisplay.affixes(for: viewModel.currencyCode)
  }

  /// Converts between the draft `Decimal?` and the field's `String` for the expense's currency/locale.
  var amountConverter: OptionalDecimalFormatStyle {
    OptionalDecimalFormatStyle(currencyCode: viewModel.currencyCode)
  }

  /// Styled, VoiceOver-hidden currency affix shown beside the amount field. Renders nothing for an empty
  /// affix so only the locale-correct side appears. The amount's value is already announced by the field's
  /// `accessibilityLabel`, so the affix is decorative. Tracks the Add Funds tint like the field itself.
  @ViewBuilder
  private func amountAffix(_ text: String) -> some View {
    if !text.isEmpty {
      Text(text)
        .font(.title2.weight(.semibold))
        .foregroundStyle(viewModel.isAddFunds ? Color.moneySurplus : .secondary)
        .accessibilityHidden(true)
    }
  }
}
