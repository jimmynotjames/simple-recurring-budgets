import SwiftUI
import UIKit

// iOS-COMPAT(17+): two SwiftUI TextField bugs make a UIViewRepresentable wrapper necessary here.
//   Bug 1 — TextField(value:format:) rejects keystrokes when the parse strategy throws; silently blocks
//            all input on Arabic and other non-Western-digit locales. Unresolved as of iOS 26.x.
//   Bug 2 — TextField(text:)+.onChange on an @Observable model fails to render typed characters until the
//            field resigns first responder. Confirmed iOS 17+ regression.
//   When fixed upstream: remove this file and the UIKit interop; return to a native SwiftUI TextField.
//   Related workaround: the XCUITest double-tap in AccessibilityAuditTests.createBudget compensates for
//   the same UIViewRepresentable first-responder focus quirk. Search "iOS-COMPAT" to find all tagged sites.

/// A money-amount text field backed by `UITextField` rather than SwiftUI's `TextField`,
/// which is unreliable here in two ways:
/// 1. `TextField(value:format:)` rejects a keystroke whenever the parse strategy throws,
///    silently blocking all input in RTL / non-Western-digit locales (e.g. Arabic).
/// 2. `TextField(text:)` + `.onChange` writing to an `@Observable` model doesn't render typed
///    text until the field resigns first responder (iOS 17+ binding bug).
///
/// `UITextField` owns its text and reports edits via its delegate, with no SwiftUI binding
/// round-trip while editing. Callers parse `text` into a `Decimal?` (see
/// `EditableAmountConverter`).
///
/// The delegate also caps input live to the currency's minor-unit precision: no decimal
/// separator for 0-decimal currencies (JPY, KRW, …), else at most `maxFractionDigits`
/// fraction digits.
///
/// This is a workaround, not a preference (issue #122). If either bug is fixed, replace it
/// with a native field; `EditableAmountConverter` holds the reusable conversion logic.
/// Re-verify the Arabic / JPY / BHD / EUR cases first.
struct DecimalInputField: UIViewRepresentable {
  let placeholder: String
  @Binding var text: String
  /// ISO 4217 code whose minor-unit count caps fraction digits during entry.
  var currencyCode: String
  /// Locale whose decimal separator is recognized while capping. Defaults to the user's locale.
  var locale: Locale = .autoupdatingCurrent
  /// Become first responder once when the field first appears (used for the expense Amount field in Add mode).
  var autoFocus: Bool = false
  /// Monotonic counter; each increment makes the field first responder on the next update.
  /// `CurrencyAmountField` bumps it on clear (✕) so the cursor lands here, not wherever it was.
  var focusRequest: Int = 0
  /// Text colour; the expense Amount field tints green while Add Funds is on.
  var textColor: Color = .primary
  /// VoiceOver label (the field itself; the adjacent currency affix is decorative/hidden).
  var accessibilityLabel: String
  /// Called when this field becomes first responder, so callers can sync a sibling
  /// `@FocusState`. Otherwise focus lingers on the previous SwiftUI field and iPadOS 26
  /// mis-anchors the `.decimalPad` popover to it.
  var onBeginEditing: (() -> Void)?

  private var maxFractionDigits: Int {
    EditableAmountConverter.fractionDigits(for: currencyCode, locale: locale)
  }

  /// The locale's own decimal separator, the only one `.decimalPad` emits for it (".", ",",
  /// Arabic "٫", …). Don't hardcode a dot/comma set: in comma-decimal locales "." is a
  /// grouping separator and must not count as a second decimal point.
  private var separators: Set<Character> {
    let formatter = NumberFormatter()
    formatter.locale = locale
    formatter.numberStyle = .decimal
    guard let separator = formatter.decimalSeparator?.first else { return ["."] }
    return [separator]
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
    // Overwrite only on real divergence, to preserve an in-progress edit and cursor.
    if field.text != text {
      field.text = text
    }
    apply(to: field, context: context)
    if autoFocus, !context.coordinator.didAutoFocus {
      context.coordinator.didAutoFocus = true
      Task { field.becomeFirstResponder() }
    }
    if context.coordinator.lastFocusRequest != focusRequest {
      context.coordinator.lastFocusRequest = focusRequest
      // Deferred (`Task`) like autoFocus: first-responder setup mid-update is the fragile
      // spot behind the iOS 26 crash noted on `CurrencyAmountField.onClear`. Never call
      // becomeFirstResponder inside the update pass.
      if !field.isFirstResponder {
        Task { field.becomeFirstResponder() }
      }
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(
      text: $text,
      maxFractionDigits: maxFractionDigits,
      separators: separators,
      lastFocusRequest: focusRequest
    )
  }

  private func apply(to field: UITextField, context: Context) {
    field.placeholder = placeholder
    field.textColor = UIColor(textColor)
    field.accessibilityLabel = accessibilityLabel
    // Keep capping rules current if currency/locale change.
    context.coordinator.maxFractionDigits = maxFractionDigits
    context.coordinator.separators = separators
    context.coordinator.onBeginEditing = onBeginEditing
  }

  /// Semibold Title2 that scales with Dynamic Type.
  private static var font: UIFont {
    let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .title2)
      .addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: UIFont.Weight.semibold]])
    return UIFont(descriptor: descriptor, size: 0)
  }

  /// Whether `prospective` is acceptable under the `maxFractionDigits` cap, treating any
  /// character in `separators` as the decimal separator. Pure (unit-tested). 0-decimal
  /// currencies reject any separator; otherwise at most `maxFractionDigits` digits may
  /// follow a single separator.
  static func isAcceptable(
    _ prospective: String,
    maxFractionDigits: Int,
    separators: Set<Character>
  ) -> Bool {
    if prospective.isEmpty {
      return true
    }
    let separatorCount = prospective.count { separators.contains($0) }
    if maxFractionDigits == 0 {
      return separatorCount == 0
    }
    if separatorCount > 1 {
      return false
    }
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
    /// Last `focusRequest` acted on; seeded from the initial value so the field doesn't
    /// grab focus on first update.
    var lastFocusRequest: Int
    var onBeginEditing: (() -> Void)?

    init(
      text: Binding<String>,
      maxFractionDigits: Int,
      separators: Set<Character>,
      lastFocusRequest: Int
    ) {
      _text = text
      self.maxFractionDigits = maxFractionDigits
      self.separators = separators
      self.lastFocusRequest = lastFocusRequest
    }

    func textFieldDidBeginEditing(_: UITextField) {
      onBeginEditing?()
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
