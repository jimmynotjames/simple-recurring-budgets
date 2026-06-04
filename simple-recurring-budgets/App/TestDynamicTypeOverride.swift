import SwiftUI

/// Test-only hook to force the app's Dynamic Type size at launch.
///
/// The standard `-UIPreferredContentSizeCategoryName` launch argument proved unreliable on the
/// iOS 26.x simulator (it rendered at the default size), so the ad-hoc localized-layout screenshot
/// check (`scripts/translation-accessibility-size-check/`) forces the size through this env hook
/// instead — it's deterministic and parallel-safe (per-launch environment).
///
/// **Inert in normal use:** only active when the process is launched under `IS_TESTING` *and* with
/// `FORCE_DYNAMIC_TYPE` set (e.g. `FORCE_DYNAMIC_TYPE=xxxLarge`). Production never sets these, so this
/// applies no override — same gating precedent as `IS_TESTING` elsewhere in the app.
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
