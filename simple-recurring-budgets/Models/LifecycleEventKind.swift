import Foundation

/// The kind of a budget lifecycle event.
///
/// **Storage convention:** `LifecycleEvent` stores `kindRawValue: String` and exposes a typed `kind`
/// accessor (same as `Budget.period`). SwiftData can serialize Codable enums directly, but such a property
/// is opaque to `#Predicate` (`#Predicate<LifecycleEvent> { $0.kind == .pause }` can't compile). Storing
/// the raw string keeps fetch-by-kind queries possible.
enum LifecycleEventKind: String, Codable, CaseIterable {
  case pause
  case resume
}
