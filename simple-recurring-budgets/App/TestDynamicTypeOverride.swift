import SwiftUI

#if DEBUG
  /// Test-only hook forcing the Dynamic Type size at launch. `-UIPreferredContentSizeCategoryName` is
  /// unreliable on the iOS 26.x simulator (renders at default), so the localized-layout screenshot check
  /// (`scripts/translation-accessibility-size-check/`) uses this per-launch env hook instead.
  ///
  /// DEBUG-only (compiled out of Release) and inert unless launched under `IS_TESTING` with
  /// `FORCE_DYNAMIC_TYPE` set (e.g. `xxxLarge`), which only XCUITest does. Its call sites (App root,
  /// `RootView` sheet) are `#if DEBUG` too.
  struct TestDynamicTypeOverride: ViewModifier {
    func body(content: Content) -> some View {
      if let size = Self.forced {
        content.dynamicTypeSize(size)
      } else {
        content
      }
    }

    /// The forced size, or `nil` when not under test or unset/unrecognized.
    static var forced: DynamicTypeSize? {
      let env = ProcessInfo.processInfo.environment
      guard env["IS_TESTING"] != nil, let raw = env["FORCE_DYNAMIC_TYPE"] else { return nil }
      switch raw {
      case "xSmall": return .xSmall
      case "small": return .small
      case "medium": return .medium
      case "large": return .large
      case "xLarge": return .xLarge
      case "xxLarge": return .xxLarge
      case "xxxLarge": return .xxxLarge
      case "accessibility1": return .accessibility1
      case "accessibility2": return .accessibility2
      case "accessibility3": return .accessibility3
      case "accessibility4": return .accessibility4
      case "accessibility5": return .accessibility5
      default: return nil
      }
    }
  }
#endif
