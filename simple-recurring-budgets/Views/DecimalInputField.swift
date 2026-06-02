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
/// (see `EditableAmountConverter`). This mirrors how community currency-field libraries are built.
///
/// The delegate also caps input to the currency's minor-unit precision live: no decimal separator at all for
/// 0-decimal currencies (JPY, KRW, …), and at most `maxFractionDigits` fraction digits otherwise.
///
/// **Revisit when SwiftUI improves (tracked in issue #122):** this is a workaround, not a preference. If
/// either bug above is fixed in a future iOS, delete this wrapper and the UIKit interop and move back to a
/// native SwiftUI field — `TextField(value:format:)` if the parse round-trip becomes reliable, or
/// `TextField(text:)` + `.onChange` otherwise. `EditableAmountConverter` already holds the
/// conversion/seed/parse logic the native path would reuse, and `.decimalPad` + a number `FormatStyle` would
/// cover most of the fraction capping done here by hand. Re-verify the Arabic / JPY / BHD / EUR cases first.
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
  /// Called when this field becomes first responder. Callers use it to keep a sibling SwiftUI
  /// `@FocusState` in sync — without it, focus state lingers on a previously focused SwiftUI field,
  /// which on iPadOS 26 mis-anchors the `.decimalPad` popover to that stale field (issue #126).
  var onBeginEditing: (() -> Void)?

  private var maxFractionDigits: Int {
    EditableAmountConverter.fractionDigits(for: currencyCode, locale: locale)
  }

  /// Decimal-separator character(s) to recognize while capping fraction digits: exactly the locale's own
  /// separator — the only one the `.decimalPad` emits for this locale (".", ",", Arabic "٫", …). Deriving it
  /// from the locale rather than hardcoding a dot/comma grab-bag keeps the cap correct in comma-decimal
  /// locales, where a "." is a *grouping* separator and must not be miscounted as a second decimal point.
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
    context.coordinator.onBeginEditing = onBeginEditing
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
    var onBeginEditing: (() -> Void)?

    init(text: Binding<String>, maxFractionDigits: Int, separators: Set<Character>) {
      _text = text
      self.maxFractionDigits = maxFractionDigits
      self.separators = separators
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
