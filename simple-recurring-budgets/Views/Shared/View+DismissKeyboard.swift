import SwiftUI
import UIKit

extension View {
  /// Resigns the current first responder, dismissing the software keyboard.
  ///
  /// Sends `resignFirstResponder` up the responder chain instead of toggling a `@FocusState`,
  /// so one call covers both SwiftUI `TextField`s and the UIKit-backed `DecimalInputField`.
  func dismissKeyboard() {
    UIApplication.shared.sendAction(
      #selector(UIResponder.resignFirstResponder),
      to: nil,
      from: nil,
      for: nil
    )
  }
}
