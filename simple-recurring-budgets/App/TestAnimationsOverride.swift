import SwiftUI
import UIKit

#if DEBUG
  /// Test-only hook to turn animations off at launch, for CI's UI tests.
  ///
  /// On CI's loaded runners, sheet presentations and SwiftUI transitions can take long enough to
  /// settle that XCUITest's taps and waits race them. Locally they settle quickly, so local runs keep
  /// their animations.
  ///
  /// The switch: CI sets `TEST_RUNNER_FORCE_ANIMATIONS=off` on its UI-test jobs; xcodebuild hands it
  /// to the test runner as `FORCE_ANIMATIONS`, and `makeApp()` (UITestHelpers.swift) passes it on to
  /// the app's environment (AGENTS.md §CI covers reproducing it locally).
  ///
  /// Compiled out of Release. Even in DEBUG it does nothing unless the app is launched by a UI test
  /// (`UI_TESTS=1`) with `FORCE_ANIMATIONS=off`. It deliberately ignores `IS_TESTING`: the scheme
  /// sets that for the unit tests' host app too, which keeps its animations. Code that disables UIKit
  /// animations temporarily must scope it (`UIView.performWithoutAnimation`), not set them back to
  /// `true`.
  enum TestAnimationsOverride {
    static let isActive: Bool = {
      let env = ProcessInfo.processInfo.environment
      return env["UI_TESTS"] == "1" && env["FORCE_ANIMATIONS"] == "off"
    }()

    /// UIKit: view animations and sheet presentations become instant.
    static func applyToUIKit() {
      if isActive {
        UIView.setAnimationsEnabled(false)
      }
    }

    /// SwiftUI: `.animation` modifiers and `withAnimation` under the view it's applied to. Each sheet's
    /// content is its own hosting root, so sheet content applies it again.
    struct Modifier: ViewModifier {
      func body(content: Content) -> some View {
        if TestAnimationsOverride.isActive {
          content.transaction { transaction in
            transaction.disablesAnimations = true
            transaction.animation = nil
          }
        } else {
          content
        }
      }
    }
  }
#endif
