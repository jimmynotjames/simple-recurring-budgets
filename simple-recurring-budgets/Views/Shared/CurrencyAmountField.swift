import SwiftUI

/// A money-amount editor: a keypad `DecimalInputField` flanked by the locale-correct currency
/// affix (per `CurrencyDisplayPreference.affixes`). Used by the expense Amount card and the
/// budget Allocation card; see `EditableAmountConverter` (seed/parse) and `DecimalInputField`
/// (why UIKit-backed).
///
/// The internal editable `String` is load-bearing: it preserves in-progress entries like `"1."`
/// or `"1.50"` that a `Decimal` round-trip would collapse mid-keystroke.
///
/// Sync is bidirectional, disambiguated by `lastSyncedValue`. Keystrokes flow text → value
/// (`onChange(of: text)` parses and writes the binding); external writes flow value → text
/// (`onChange(of: value)` re-seeds). The re-seed fires only when the new value differs from
/// the last one this field wrote, so own writes never cascade, and `"1."` survives because it
/// parses to the same `value` (1) as before.
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
  /// Called when the underlying field becomes first responder. The budget screen clears the
  /// Name field's `@FocusState` here; otherwise the iPadOS 26 `.decimalPad` popover anchors
  /// to the stale Name field.
  var onBeginEditing: (() -> Void)?
  /// When non-nil and `value` is non-nil, shows a trailing ✕ that calls this. The button
  /// stays inside the existing HStack on purpose: wrapping the UIViewRepresentable in a new
  /// outer container crashes on iOS 26 during autoFocus first-responder setup.
  var onClear: (() -> Void)?

  @State private var text: String = ""
  /// Bumped on clear (✕) so `DecimalInputField` retakes first responder; otherwise the cursor
  /// stays wherever it was (e.g. the Description field after a Recents fill).
  @State private var focusRequest = 0
  /// Last `value` this field round-tripped (seeded on appear, updated on every text→value
  /// parse). `onChange(of: value)` skips the re-seed when equal, i.e. the change was our own
  /// parse; external writes (e.g. a Recents tap) differ and re-seed `text`.
  @State private var lastSyncedValue: Decimal?

  private var converter: EditableAmountConverter {
    EditableAmountConverter(currencyCode: currencyCode)
  }

  private var affixes: (leading: String, trailing: String) {
    currencyDisplay.affixes(for: currencyCode)
  }

  var body: some View {
    HStack(alignment: .center, spacing: 2) {
      affix(affixes.leading)
      DecimalInputField(
        placeholder: placeholder,
        text: $text,
        currencyCode: currencyCode,
        autoFocus: autoFocus,
        focusRequest: focusRequest,
        textColor: tint ?? .primary,
        accessibilityLabel: accessibilityLabel,
        onBeginEditing: onBeginEditing
      )
      .frame(maxWidth: .infinity)
      affix(affixes.trailing)
      if let onClear, value != nil {
        Button {
          onClear()
          focusRequest += 1
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.secondary)
            .font(.body)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(
          localized: "currencyAmountField.clearButton.accessibilityLabel",
          defaultValue: "Clear amount",
          comment: "VoiceOver label for the trailing clear button inside CurrencyAmountField"
        ))
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .onAppear {
      text = converter.editableText(value)
      lastSyncedValue = value
    }
    .onChange(of: value) { _, newValue in
      // External write: re-seed the display.
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

  /// Currency affix; empty affixes render nothing so only the locale-correct side shows.
  /// VoiceOver-hidden: the field's `accessibilityLabel` already announces the value.
  @ViewBuilder
  private func affix(_ text: String) -> some View {
    if !text.isEmpty {
      Text(text)
        .font(.title2.weight(.semibold))
        .foregroundStyle(tint.map(AnyShapeStyle.init) ?? .readableSecondary)
        .accessibilityHidden(true)
    }
  }
}
