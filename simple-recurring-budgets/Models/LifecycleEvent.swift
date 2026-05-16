import Foundation
import SwiftData

/// Records a pause or resume lifecycle event for a `Budget`.
///
/// Pause and resume operate at whole-period granularity: the period *containing* the event
/// is itself active; pausing takes effect the period after. `lastModified` breaks ties for
/// CloudKit cross-device convergence.
///
/// `kind` is stored as `kindRawValue: String` and exposed via a typed `kind` accessor so
/// that `#Predicate<LifecycleEvent>` queries can filter by kind. See `LifecycleEventKind`
/// for the rationale.
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
