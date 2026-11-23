import Foundation
import SwiftData

/// A pause or resume event for a `Budget`. Pause/resume work at whole-period granularity: the period
/// *containing* the event stays active; pausing takes effect the period after. `lastModified` breaks ties
/// for CloudKit convergence.
///
/// `kind` is stored as `kindRawValue: String` behind a typed `kind` accessor so `#Predicate<LifecycleEvent>`
/// can filter by kind (see `LifecycleEventKind`).
@Model
final class LifecycleEvent {
  var id: UUID = UUID()
  /// Stored as `LifecycleEventKind.rawValue`. Read/write via `kind`.
  var kindRawValue: String = LifecycleEventKind.pause.rawValue
  var effectiveDate: Date = Date()
  var lastModified: Date = Date()

  var budget: Budget?

  var kind: LifecycleEventKind {
    get { LifecycleEventKind(rawValue: kindRawValue) ?? .pause }
    set { kindRawValue = newValue.rawValue }
  }

  init(kind: LifecycleEventKind, effectiveDate: Date, lastModified: Date = Date()) {
    kindRawValue = kind.rawValue
    self.effectiveDate = effectiveDate
    self.lastModified = lastModified
  }
}
