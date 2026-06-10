import SwiftUI

struct CurrencyPickerView: View {
  @Binding var selection: String
  @Environment(\.dismiss) private var dismiss

  @State private var query: String = ""

  var body: some View {
    NavigationStack {
      List {
        ForEach(filteredCodes, id: \.self) { code in
          currencyRow(code: code)
        }
      }
      .scrollContentBackground(.hidden)
      .searchable(
        text: $query,
        prompt: String(
          localized: "currencyPicker.search.prompt",
          defaultValue: "Search currencies",
          comment: "Placeholder in the currency picker search bar"
        )
      )
      .navigationTitle(String(
        localized: "currencyPicker.navigationTitle",
        defaultValue: "Currency",
        comment: "Navigation bar title for the currency picker sheet"
      ))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(String(
            localized: "common.action.cancel",
            defaultValue: "Cancel",
            comment: "Generic Cancel button reused by multiple confirmation dialogs, alerts, and sheets across the app"
          )) {
            dismiss()
          }
        }
      }
      .appBackground()
    }
  }

  // MARK: - Row

  private func currencyRow(code: String) -> some View {
    let isSelected = code == selection
    let name = displayName(for: code)
    let rowLabel = name.map { localizedName in
      String(
        localized: "currencyPicker.row.accessibilityLabel",
        defaultValue: "\(code), \(localizedName)",
        comment: "VoiceOver label for a currency row in the picker that has a localized display name. First argument is the ISO 4217 code (e.g. USD); second is the localized display name (e.g. US Dollar)."
      )
    } ?? String(
      localized: "currencyPicker.row.accessibilityLabel.codeOnly",
      defaultValue: "\(code)",
      comment: "VoiceOver label for a currency row in the picker when no localized display name is available. Argument is the ISO 4217 code."
    )
    let selectedValue = isSelected
      ? String(
        localized: "currencyPicker.row.selected.accessibilityValue",
        defaultValue: "Selected",
        comment: "VoiceOver value appended to the currently-selected currency row in the picker"
      )
      : ""
    return Button {
      selection = code
      dismiss()
    } label: {
      HStack {
        Text(code)
          .font(.body.monospacedDigit())
        if let name {
          Text(name)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
          Spacer()
        }
        if isSelected {
          Image(systemName: "checkmark")
            .foregroundStyle(Color.accentColor)
        }
      }
    }
    .foregroundStyle(.primary)
    .listRowBackground(Color("CellBackground"))
    // Coalesce the row's children (code + name + checkmark) into a
    // single VoiceOver element with the explicit composed label, so
    // VO reads "USD, US Dollar" rather than as two static-text rows.
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(rowLabel)
    .accessibilityValue(selectedValue)
  }

  // MARK: - Helpers

  private var allCodes: [String] {
    Array(Set(Locale.commonISOCurrencyCodes)).sorted()
  }

  private var filteredCodes: [String] {
    guard !query.isEmpty else { return allCodes }
    return allCodes.filter { code in
      code.localizedCaseInsensitiveContains(query)
        || (displayName(for: code)?.localizedCaseInsensitiveContains(query) ?? false)
    }
  }

  static func displayName(for code: String) -> String? {
    Locale.current.localizedString(forCurrencyCode: code)
  }

  private func displayName(for code: String) -> String? {
    Self.displayName(for: code)
  }
}

// MARK: - Preview

#Preview("Light") {
  CurrencyPickerView(selection: .constant("USD"))
}

#Preview("Dark") {
  CurrencyPickerView(selection: .constant("USD"))
    .preferredColorScheme(.dark)
}

#Preview("Accessibility Dynamic Type") {
  CurrencyPickerView(selection: .constant("USD"))
    .environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge)
}
