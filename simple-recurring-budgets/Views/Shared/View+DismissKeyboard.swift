import SwiftUI
import UIKit

extension View {
  /// Resigns the current first responder, dismissing the software keyboard.
  ///
  /// Sends `resignFirstResponder` up the responder chain rather than toggling a specific
  /// `@FocusState`, so it dismisses whatever is focused without the caller having to know
  /// which field that is. This matters on screens that mix a SwiftUI `TextField` with a
  /// UIKit-backed field (`DecimalInputField`): a single call covers both.
  func dismissKeyboard() {
    UIApplication.shared.sendAction(
      #selector(UIResponder.resignFirstResponder),
      to: nil,
      from: nil,
      for: nil
    )
  }
}
