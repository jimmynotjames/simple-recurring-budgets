import SwiftUI

extension View {
  /// Runs `action` when the calendar day changes while the view is alive.
  ///
  /// Lets a screen left open across midnight refresh: every budget period boundary falls
  /// on a local midnight, so `.NSCalendarDayChanged` means "a period may have rolled over".
  /// The system also posts it on time-zone and significant clock changes, which is wanted
  /// since lifecycle math uses `Calendar.autoupdatingCurrent`. Runs in a `.task`, so it's
  /// cancelled when the view disappears.
  func onCalendarDayChange(perform action: @escaping () -> Void) -> some View {
    task {
      let notifications = NotificationCenter.default.notifications(named: .NSCalendarDayChanged)
      for await _ in notifications {
        action()
      }
    }
  }
}
