import SwiftUI

// MARK: - Allocation card

extension AddEditBudgetView {
  var allocationCard: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 8) {
        HStack(alignment: .center, spacing: 12) {
          CurrencyAmountField(
            value: $viewModel.allocation,
            currencyCode: viewModel.currencyCode,
            currencyDisplay: settings.currencyDisplay,
            placeholder: String(
              localized: "addEditBudget.field.allocation.placeholder",
              defaultValue: "0",
              comment: "Placeholder in the allocation amount field when no value is entered"
            ),
            accessibilityLabel: String(
              localized: "addEditBudget.field.allocation.accessibilityLabel",
              defaultValue: "Allocation amount, \((viewModel.allocation ?? 0).formatted(currencyCode: viewModel.currencyCode, display: settings.currencyDisplay))",
              comment: "VoiceOver label for the allocation field; argument is the formatted monetary amount including currency"
            )
          )

          Button {
            // Retire the keyboard before the currency sheet covers it, so it doesn't
            // spring back up when the sheet is dismissed.
            dismissKeyboard()
            showCurrencyPicker = true
          } label: {
            HStack(spacing: 4) {
              Text(viewModel.currencyCode)
                .font(.callout.weight(.medium))
              Image(systemName: "chevron.up.chevron.down")
                .font(.caption2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.secondary.opacity(0.12)))
            .foregroundStyle(.secondary)
          }
          .buttonStyle(.plain)
          .accessibilityLabel(String(
            localized: "addEditBudget.field.currency.accessibilityLabel",
            defaultValue: "Currency, \(viewModel.currencyCode)",
            comment: "VoiceOver label for the currency selection pill showing the current ISO code"
          ))
          .accessibilityHint(String(
            localized: "addEditBudget.field.currency.accessibilityHint",
            defaultValue: "Opens currency picker",
            comment: "VoiceOver hint for the currency selection pill"
          ))
        }

        if !initialCurrencyCode.isEmpty, viewModel.currencyCode != initialCurrencyCode {
          Text(String(
            localized: "addEditBudget.note.currencyLabelOnly",
            defaultValue: "Changing currency only updates the label. I.e. No currency conversion.",
            comment: "Inline note shown below the currency picker when the user selects a different currency, warning that no conversion is applied"
          ))
          .font(.caption)
          .foregroundStyle(.secondary)
          .transition(.opacity.combined(with: .move(edge: .top)))
        }
      }
      .animation(.easeInOut(duration: 0.2), value: viewModel.currencyCode)
    } label: {
      sectionLabel(String(
        localized: "addEditBudget.section.allocation",
        defaultValue: "Allocation",
        comment: "Section header above the allocation amount and currency fields"
      ))
    }
    .backgroundStyle(Color("CellBackground"))
    .onChange(of: viewModel.currencyCode) { _, newCode in
      guard !initialCurrencyCode.isEmpty, newCode != initialCurrencyCode else { return }
      let disclaimer = String(
        localized: "addEditBudget.note.currencyLabelOnly",
        defaultValue: "Changing currency only updates the label. I.e. No currency conversion.",
        comment: "Inline note shown below the currency picker when the user selects a different currency, warning that no conversion is applied"
      )
      AccessibilityNotification.Announcement(disclaimer).post()
    }
  }
}
