import Foundation

/// The kind of a budget lifecycle event.
///
/// **Storage convention:** `LifecycleEvent` stores `kindRawValue: String` (the enum's raw
/// value) and exposes a typed `kind: LifecycleEventKind` computed accessor. SwiftData
/// *can* serialize Codable enums directly, but a Codable-backed property is opaque to
/// `#Predicate` — you cannot write `#Predicate<LifecycleEvent> { $0.kind == .pause }`
/// because the predicate compiler can't see into the encoded payload. Storing the raw
/// string keeps that door open for future fetch-by-kind queries. Same convention as
/// `Budget.period`.
enum LifecycleEventKind: String, Codable, CaseIterable {
  case pause
  case resume
}
