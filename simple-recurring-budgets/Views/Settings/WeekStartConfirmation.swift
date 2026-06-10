import Foundation

/// State machine for the Settings "Week Starts On" confirmation flow: a picker
/// selection is held as `pending` until the user confirms (commit) or cancels
/// (discard) in the alert. Extracted from `SettingsView` so unit tests drive the
/// same transitions the view renders (test-coverage-audit-2026-06-10 D2).
struct WeekStartConfirmation {
  private(set) var pending: Weekday?

  /// Drives the alert's `isPresented` binding.
  var isPresenting: Bool {
    pending != nil
  }

  /// Picker set-path: selecting the already-active day is a no-op; anything
  /// else parks the selection pending confirmation.
  mutating func select(_ newDay: Weekday, current: Weekday) {
    guard newDay != current else { return }
    pending = newDay
  }

  /// Alert confirm: returns the day to commit (nil if nothing was pending)
  /// and clears the pending state.
  mutating func confirm() -> Weekday? {
    defer { pending = nil }
    return pending
  }

  /// Alert cancel (or dismissal via the `isPresented` binding).
  mutating func cancel() {
    pending = nil
  }
}
