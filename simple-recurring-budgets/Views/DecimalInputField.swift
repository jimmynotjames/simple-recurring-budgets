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
struct DecimalInputField: UIViewRepresentable {
  let placeholder: String
  @Binding var text: String
  /// Become first responder once when the field first appears (used for the expense Amount field in Add mode).
  var autoFocus: Bool = false
  /// Text colour; the expense Amount field tints green while Add Funds is on.
  var textColor: Color = .primary
  /// VoiceOver label (the field itself; the adjacent currency affix is decorative/hidden).
  var accessibilityLabel: String

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
    apply(to: field)
    return field
  }

  func updateUIView(_ field: UITextField, context: Context) {
    // Only overwrite when the model genuinely diverges, so we never clobber an in-progress edit / cursor.
    if field.text != text {
      field.text = text
    }
    apply(to: field)
    if autoFocus, !context.coordinator.didAutoFocus {
      context.coordinator.didAutoFocus = true
      Task { field.becomeFirstResponder() }
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(text: $text)
  }

  private func apply(to field: UITextField) {
    field.placeholder = placeholder
    field.textColor = UIColor(textColor)
    field.accessibilityLabel = accessibilityLabel
  }

  /// Semibold Title2 that scales with Dynamic Type.
  private static var font: UIFont {
    let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .title2)
      .addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: UIFont.Weight.semibold]])
    return UIFont(descriptor: descriptor, size: 0)
  }

  final class Coordinator: NSObject, UITextFieldDelegate {
    @Binding private var text: String
    var didAutoFocus = false

    init(text: Binding<String>) {
      _text = text
    }

    @objc func editingChanged(_ field: UITextField) {
      text = field.text ?? ""
    }
  }
}
