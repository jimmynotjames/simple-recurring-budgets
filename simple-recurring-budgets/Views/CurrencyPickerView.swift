//
//  CurrencyPickerView.swift
//  simple-recurring-budgets
//

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
                        localized: "addEditBudget.action.cancel",
                        defaultValue: "Cancel",
                        comment: "Button that dismisses the Add/Edit Budget sheet without saving"
                    )) {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Row

    private func currencyRow(code: String) -> some View {
        let isSelected = code == selection
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
                if let name = displayName(for: code) {
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

#Preview {
    CurrencyPickerView(selection: .constant("USD"))
}
