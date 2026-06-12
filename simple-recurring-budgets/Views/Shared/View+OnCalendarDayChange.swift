import SwiftUI

extension View {
  /// Runs `action` when the calendar day changes while the view is alive.
  ///
  /// Closes the foregrounded-rollover gap (issue #70, audit L3): every budget
  /// period boundary — daily, weekly, biweekly, monthly — falls on a local
  /// midnight, so `.NSCalendarDayChanged` is precisely the "a period may have
  /// rolled over" signal. The system also posts it on time-zone changes and
  /// significant clock changes, which is desirable here: lifecycle math runs on
  /// `Calendar.autoupdatingCurrent`, so those shifts can move period boundaries
  /// too. Without this, a budget screen left open across midnight keeps showing
  /// the closed period until a scene-phase change or a data write triggers a
  /// refresh.
  ///
  /// Same `NotificationCenter.notifications(named:)` async-sequence pattern as
  /// `SettingsView.observeSingleNotification` — the observation lives in a
  /// `.task`, so it is cancelled automatically when the view disappears.
  func onCalendarDayChange(perform action: @escaping () -> Void) -> some View {
    task {
      let notifications = NotificationCenter.default.notifications(named: .NSCalendarDayChanged)
      for await _ in notifications {
        action()
      }
    }
  }
}
