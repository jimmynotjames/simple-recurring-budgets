import SwiftUI
import UIKit

/// A money-amount text field backed by `UITextField` rather than SwiftUI's `TextField`.
///
/// SwiftUI's `TextField` proved unreliable for this field in two distinct ways:
/// 1. `TextField(value:format:)` rejects a keystroke whenever the parse strategy throws — which silently
///    blocked *all* input in RTL / non-Western-digit locales (e.g. Arabic), where the proposed string isn't
///    what a Western-digit parser expects.
/// 2. `TextField(text:)` + `.onChange` that writes to an `@Observable` model fails to render typed text until
///    the field resigns first responder (a known iOS 17+ binding bug).
///
/// Wrapping `UITextField` sidesteps both: the text view owns its text and reports edits via its delegate,
/// with no SwiftUI binding round-trip during editing. Callers parse `text` into a `Decimal?` themselves
/// (see `OptionalDecimalFormatStyle`). This mirrors how community currency-field libraries are built.
///
/// The delegate also caps input to the currency's minor-unit precision live: no decimal separator at all for
/// 0-decimal currencies (JPY, KRW, …), and at most `maxFractionDigits` fraction digits otherwise.
struct DecimalInputField: UIViewRepresentable {
  let placeholder: String
  @Binding var text: String
  /// ISO 4217 code whose minor-unit count caps fraction digits during entry.
  var currencyCode: String
  /// Locale whose decimal separator is recognized while capping. Defaults to the user's locale.
  var locale: Locale = .autoupdatingCurrent
  /// Become first responder once when the field first appears (used for the expense Amount field in Add mode).
  var autoFocus: Bool = false
  /// Text colour; the expense Amount field tints green while Add Funds is on.
  var textColor: Color = .primary
  /// VoiceOver label (the field itself; the adjacent currency affix is decorative/hidden).
  var accessibilityLabel: String

  private var maxFractionDigits: Int {
    OptionalDecimalFormatStyle.fractionDigits(for: currencyCode, locale: locale)
  }

  /// Decimal-separator characters to recognize while capping fraction digits. Includes the locale's own
  /// separator (what the `.decimalPad` emits) plus common variants so paste/edge cases are handled.
  private var separators: Set<Character> {
    let formatter = NumberFormatter()
    formatter.locale = locale
    formatter.numberStyle = .decimal
    var set: Set<Character> = [".", ",", "\u{066B}"] // dot, comma, Arabic decimal separator
    if let localeSeparator = formatter.decimalSeparator?.first {
      set.insert(localeSeparator)
    }
    return set
  }

  func makeUIView(context: Context) -> UITextField {
    let field = UITextField()
    field.delegate = context.coordinator
    field.keyboardType = .decimalPad
    field.textAlignment = .natural // RTL-aware
    field.adjustsFontForContentSizeCategory = true
    field.font = Self.font
    field.addTarget(
      context.coordinator,
      action: #selector(Coordinator.editingChanged(_:)),
      for: .editingChanged
    )
    field.setContentHuggingPriority(.defaultLow, for: .horizontal)
    field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    apply(to: field, context: context)
    return field
  }

  func updateUIView(_ field: UITextField, context: Context) {
    // Only overwrite when the model genuinely diverges, so we never clobber an in-progress edit / cursor.
    if field.text != text {
      field.text = text
    }
    apply(to: field, context: context)
    if autoFocus, !context.coordinator.didAutoFocus {
      context.coordinator.didAutoFocus = true
      Task { field.becomeFirstResponder() }
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(text: $text, maxFractionDigits: maxFractionDigits, separators: separators)
  }

  private func apply(to field: UITextField, context: Context) {
    field.placeholder = placeholder
    field.textColor = UIColor(textColor)
    field.accessibilityLabel = accessibilityLabel
    // Keep the coordinator's capping rules current if the currency/locale changed.
    context.coordinator.maxFractionDigits = maxFractionDigits
    context.coordinator.separators = separators
  }

  /// Semibold Title2 that scales with Dynamic Type.
  private static var font: UIFont {
    let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .title2)
      .addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: UIFont.Weight.semibold]])
    return UIFont(descriptor: descriptor, size: 0)
  }

  /// Whether `prospective` is acceptable for a field capped at `maxFractionDigits`, treating any character in
  /// `separators` as a decimal separator. Pure and side-effect-free so it can be unit-tested:
  /// - 0-decimal currencies reject any decimal separator (no fractional entry at all).
  /// - otherwise at most `maxFractionDigits` digits may follow a single separator.
  static func isAcceptable(
    _ prospective: String,
    maxFractionDigits: Int,
    separators: Set<Character>
  ) -> Bool {
    if prospective.isEmpty { return true }
    let separatorCount = prospective.count { separators.contains($0) }
    if maxFractionDigits == 0 { return separatorCount == 0 }
    if separatorCount > 1 { return false }
    guard let separatorIndex = prospective.firstIndex(where: { separators.contains($0) }) else {
      return true
    }
    let fraction = prospective[prospective.index(after: separatorIndex)...]
    return fraction.count <= maxFractionDigits
  }

  final class Coordinator: NSObject, UITextFieldDelegate {
    @Binding private var text: String
    var maxFractionDigits: Int
    var separators: Set<Character>
    var didAutoFocus = false

    init(text: Binding<String>, maxFractionDigits: Int, separators: Set<Character>) {
      _text = text
      self.maxFractionDigits = maxFractionDigits
      self.separators = separators
    }

    func textField(
      _ textField: UITextField,
      shouldChangeCharactersIn range: NSRange,
      replacementString string: String
    ) -> Bool {
      let current = textField.text ?? ""
      guard let stringRange = Range(range, in: current) else { return true }
      let prospective = current.replacingCharacters(in: stringRange, with: string)
      return DecimalInputField.isAcceptable(
        prospective,
        maxFractionDigits: maxFractionDigits,
        separators: separators
      )
    }

    @objc func editingChanged(_ field: UITextField) {
      text = field.text ?? ""
    }
  }
}
