import Foundation

/// Calendar weekday aligned with `Calendar.firstWeekday` (1 = Sunday … 7 = Saturday).
enum Weekday: Int, CaseIterable, Codable, Identifiable {
  case sunday = 1
  case monday = 2
  case tuesday = 3
  case wednesday = 4
  case thursday = 5
  case friday = 6
  case saturday = 7

  var id: Int {
    rawValue
  }

  /// Returns the `Weekday` for a `Calendar.firstWeekday` value, or `nil` if not in 1…7.
  static func from(calendarFirstWeekday: Int) -> Weekday? {
    Weekday(rawValue: calendarFirstWeekday)
  }
}
