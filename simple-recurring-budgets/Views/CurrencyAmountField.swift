import SwiftUI

/// A money-amount editor: a keypad-driven `DecimalInputField` flanked by the locale-correct currency
/// affix (symbol/code on the leading or trailing side per `CurrencyDisplayPreference.affixes`).
///
/// Bridges the field's editable `String` to the caller's `Decimal?` draft. The `String` is held
/// internally and is **load-bearing**: it preserves an in-progress entry like `"1."` or `"1.50"` that a
/// `Decimal` round-trip would collapse (dropping the separator or trailing zero mid-keystroke).
///
/// Synchronization is **bidirectional but disambiguated** via the `lastSyncedValue` sentinel.
/// User keystrokes flow text → value (`onChange(of: text)` parses and writes through the binding);
/// external writes to `value` flow value → text (`onChange(of: value)` re-seeds the display).
/// The sentinel tracks the last value the field itself round-tripped through `lastSyncedValue`, so
/// `onChange(of: value)` re-seeds only when the new value differs from what we just wrote — a write
/// that originated *here* never triggers a re-seed cascade. The mid-keystroke preservation of `"1."`
/// is preserved because the matching `value` (1) parsed from `"1."` is identical to the previous
/// `value` (1), so no value-change fires.
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
  /// The last `value` we round-tripped through (seeded on appear; updated on every text→value parse).
  /// `onChange(of: value)` skips the re-seed when `newValue == lastSyncedValue` — i.e., the change
  /// came from our own parse. External writes (e.g. F-7.04 Recents tap) differ from this sentinel
  /// and trigger a re-seed of `text`.
  @State private var lastSyncedValue: Decimal?

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
    .onAppear {
      text = converter.editableText(value)
      lastSyncedValue = value
    }
    .onChange(of: value) { _, newValue in
      // External write: re-seed `text` so the display reflects the new value.
      guard newValue != lastSyncedValue else { return }
      text = converter.editableText(newValue)
      lastSyncedValue = newValue
    }
    .onChange(of: text) { _, newValue in
      let parsed = try? converter.parser.parse(newValue)
      value = parsed
      lastSyncedValue = parsed
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
