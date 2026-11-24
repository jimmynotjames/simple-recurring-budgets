import SwiftUI

/// Decides whether a `scenePhase` transition should fire `app_opened`: the user bringing the app to the
/// foreground (cold launch or return from background; analytics-spec.md §9). A bare foreground is meaningful because the Budgets
/// list shows remaining amounts above the fold (glanceable checking). Transient drops to `.inactive`
/// (notification shade, Face ID, app switcher, permission dialog) are not opens.
///
/// No session/time constant: sessionization is Mixpanel's job (server-side), not the client's.
@MainActor
final class AppOpenTracker {
  private var lastPhase: ScenePhase?

  /// Records `phase` and reports whether it should fire `app_opened`: `true` on
  /// the first observed `.active` (cold launch) and on any `.background → .active`
  /// return; `false` for `.inactive → .active` flicker and non-active phases.
  func shouldFire(for phase: ScenePhase) -> Bool {
    defer { lastPhase = phase }
    guard phase == .active else { return false }
    switch lastPhase {
    case .none, .some(.background):
      return true
    default:
      return false
    }
  }
}
