import Foundation
import SwiftData

/// Records a pause or resume lifecycle event for a `Budget`.
///
/// Pause and resume operate at whole-period granularity: the period *containing* the event
/// is itself active; pausing takes effect the period after. `lastModified` breaks ties for
/// CloudKit cross-device convergence.
@Model
final class LifecycleEvent {
  var id: UUID = UUID()
  var kind: LifecycleEventKind = LifecycleEventKind.pause
  var effectiveDate: Date = Date()
  var lastModified: Date = Date()

  var budget: Budget?

  init(kind: LifecycleEventKind, effectiveDate: Date, lastModified: Date = Date()) {
    self.kind = kind
    self.effectiveDate = effectiveDate
    self.lastModified = lastModified
  }
}
