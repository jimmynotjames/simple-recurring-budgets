import SwiftUI

/// Decides whether a `scenePhase` transition should fire `app_opened`
/// (analytics-spec.md §9).
///
/// `app_opened` marks the user bringing the app to the foreground — a cold
/// launch or a return from background. Both are meaningful even with no further
/// action: the Budgets list shows remaining amounts above the fold, so a bare
/// foreground is often the user checking their numbers (glanceable
/// budget-checking). Transient interruptions that only drop the app to
/// `.inactive` — the notification shade, Face ID, the app switcher, a
/// permission dialog — are not opens and must not fire.
///
/// No session/time constant: sessionization is Mixpanel's job (server-side,
/// from the event stream), not something the client should replicate.
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
