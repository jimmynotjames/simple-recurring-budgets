import Foundation

/// Shared time-zone-aware calendar and date builders for DST / locale tests. New
/// time-zone-sensitive tests should use these, not more per-file fixed-UTC `cal` / `d(...)` copies.
enum TestCalendars {
  /// Gregorian calendar pinned to the given IANA time-zone identifier.
  static func gregorian(in timeZoneID: String) -> Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: timeZoneID)!
    return cal
  }

  /// Builds a `Date` from local wall-clock components in `calendar`'s time zone.
  static func date(
    _ year: Int, _ month: Int, _ day: Int,
    hour: Int = 0, minute: Int = 0,
    in calendar: Calendar
  ) -> Date {
    var comps = DateComponents()
    comps.year = year
    comps.month = month
    comps.day = day
    comps.hour = hour
    comps.minute = minute
    comps.second = 0
    return calendar.date(from: comps)!
  }
}
