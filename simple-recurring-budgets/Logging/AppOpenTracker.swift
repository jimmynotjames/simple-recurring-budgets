import Foundation

/// Decides whether a foreground transition should count as a new `app_opened`
/// event, approximating Mixpanel's "first foreground per session" semantics
/// (analytics-spec.md §9).
///
/// `app_opened` previously fired only from the root view's `.task`, i.e. once
/// per cold launch. A warm resume from background never re-fired it, which
/// undercounts DAU/WAU/MAU on the §3.1 Reach board. This gate lets the app fire
/// `app_opened` on every foreground transition while collapsing rapid
/// re-activations (control-center peeks, app-switcher glances, permission
/// prompts) that fall within a single Mixpanel session window.
@MainActor
final class AppOpenTracker {
  /// Inactivity gap after which a foreground counts as a new session. Matches
  /// Mixpanel's default 30-minute session timeout so the app's notion of a new
  /// "open" lines up with Mixpanel's server-side sessionization.
  static let sessionGap: TimeInterval = 30 * 60

  private var lastOpenedAt: Date?

  /// Records a foreground transition and reports whether it should fire
  /// `app_opened`. Returns `true` (and stamps `now`) on the first call and on
  /// any call at least `sessionGap` after the previous fire; returns `false`
  /// for re-activations inside that window.
  func registerForeground(now: Date = Date()) -> Bool {
    if let last = lastOpenedAt, now.timeIntervalSince(last) < Self.sessionGap {
      return false
    }
    lastOpenedAt = now
    return true
  }
}
