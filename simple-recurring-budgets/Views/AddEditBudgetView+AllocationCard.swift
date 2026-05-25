import SwiftUI

// MARK: - Allocation card

extension AddEditBudgetView {
  var allocationCard: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 8) {
        HStack(alignment: .center, spacing: 12) {
          HStack(alignment: .firstTextBaseline, spacing: 2) {
            allocationAffix(currencyAffixes.leading)
            TextField(
              String(
                localized: "addEditBudget.field.allocation.placeholder",
                defaultValue: "0",
                comment: "Placeholder in the allocation amount field when no value is entered"
              ),
              value: $viewModel.allocation,
              format: OptionalDecimalFormatStyle(currencyCode: viewModel.currencyCode)
            )
            .keyboardType(.decimalPad)
            .font(.title2.weight(.semibold).monospacedDigit())
            .accessibilityLabel(
              String(
                localized: "addEditBudget.field.allocation.accessibilityLabel",
                defaultValue: "Allocation amount, \((viewModel.allocation ?? 0).formatted(currencyCode: viewModel.currencyCode, display: settings.currencyDisplay))",
                comment: "VoiceOver label for the allocation field; argument is the formatted monetary amount including currency"
              )
            )
            allocationAffix(currencyAffixes.trailing)
          }
          .frame(maxWidth: .infinity, alignment: .leading)

          Button {
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

  /// Internal: extension-local helper. Consumed by `allocationCard` above; no other
  /// call site should read this. Leading/trailing currency decoration whose side follows
  /// the locale's currency convention (see `CurrencyDisplayPreference.affixes(for:locale:)`).
  var currencyAffixes: (leading: String, trailing: String) {
    settings.currencyDisplay.affixes(for: viewModel.currencyCode)
  }

  /// Styled, VoiceOver-hidden currency affix shown beside the allocation field. Renders nothing for an
  /// empty affix so only the locale-correct side appears. The amount's value is already announced by the
  /// field's `accessibilityLabel`, so the affix is decorative.
  @ViewBuilder
  func allocationAffix(_ text: String) -> some View {
    if !text.isEmpty {
      Text(text)
        .font(.title2.weight(.semibold))
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }
  }
}
