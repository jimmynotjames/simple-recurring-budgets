import Foundation

/// Shared time-zone-aware calendar and date builders for DST / locale tests
/// (test-coverage-audit-2026-06-10 E1). The per-file fixed-UTC `cal` / `d(...)`
/// helpers across the Domain suites predate this; new time-zone-sensitive
/// tests should use these rather than adding more per-file copies.
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
