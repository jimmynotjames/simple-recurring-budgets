import Foundation

/// The kind of a budget lifecycle event.
///
/// SwiftData serializes `String, Codable` enums automatically — store `kind` directly as
/// `LifecycleEventKind` on `LifecycleEvent`, not as a raw `String` with a separate accessor.
enum LifecycleEventKind: String, Codable, CaseIterable {
  case pause
  case resume
}
