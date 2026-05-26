import SwiftUI

/// A money-amount editor: a keypad-driven `DecimalInputField` flanked by the locale-correct currency
/// affix (symbol/code on the leading or trailing side per `CurrencyDisplayPreference.affixes`).
///
/// Bridges the field's editable `String` to the caller's `Decimal?` draft. The `String` is held
/// internally and is **load-bearing**: it preserves an in-progress entry like `"1."` or `"1.50"` that a
/// `Decimal` round-trip would collapse (dropping the separator or trailing zero mid-keystroke). The draft
/// is seeded from `value` once on appear and never re-seeded, so the field owns the text during editing
/// while the parsed `Decimal?` flows outward through the binding.
///
/// Used by both the expense Amount card and the budget Allocation card; see `EditableAmountConverter`
/// for the seed/parse logic and `DecimalInputField` for why the field is UIKit-backed.
struct CurrencyAmountField: View {
  @Binding var value: Decimal?
  let currencyCode: String
  let currencyDisplay: CurrencyDisplayPreference
  let placeholder: String
  let accessibilityLabel: String
  /// Become first responder once when the field first appears (expense Amount field in Add mode).
  var autoFocus: Bool = false
  /// When non-nil, tints both the digits and the affix (the expense field tints green while Add Funds is
  /// on). When nil, digits use `.primary` and the affix uses `.secondary`.
  var tint: Color?

  @State private var text: String = ""

  private var converter: EditableAmountConverter {
    EditableAmountConverter(currencyCode: currencyCode)
  }

  private var affixes: (leading: String, trailing: String) {
    currencyDisplay.affixes(for: currencyCode)
  }

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 2) {
      affix(affixes.leading)
      DecimalInputField(
        placeholder: placeholder,
        text: $text,
        currencyCode: currencyCode,
        autoFocus: autoFocus,
        textColor: tint ?? .primary,
        accessibilityLabel: accessibilityLabel
      )
      .frame(maxWidth: .infinity)
      affix(affixes.trailing)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .onAppear { text = converter.editableText(value) }
    .onChange(of: text) { _, newValue in
      value = try? converter.parser.parse(newValue)
    }
  }

  /// Styled, VoiceOver-hidden currency affix. Renders nothing for an empty affix so only the locale-correct
  /// side appears. The value is already announced by the field's `accessibilityLabel`, so this is decorative.
  @ViewBuilder
  private func affix(_ text: String) -> some View {
    if !text.isEmpty {
      Text(text)
        .font(.title2.weight(.semibold))
        .foregroundStyle(tint ?? .secondary)
        .accessibilityHidden(true)
    }
  }
}
