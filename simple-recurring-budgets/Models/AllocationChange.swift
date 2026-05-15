import Foundation
import SwiftData

/// Records a forward-only allocation change for a `Budget`.
///
/// Each row captures the per-period allocation in effect from `effectiveFrom` onward.
/// `lastModified` breaks ties when two rows share the same `effectiveFrom` (later wins),
/// which handles CloudKit cross-device convergence for concurrent edits.
@Model
final class AllocationChange {
  var id: UUID = UUID()
  var effectiveFrom: Date = Date()
  var amount: Decimal = 0
  var lastModified: Date = Date()

  var budget: Budget?

  init(effectiveFrom: Date, amount: Decimal, lastModified: Date = Date()) {
    self.effectiveFrom = effectiveFrom
    self.amount = amount
    self.lastModified = lastModified
  }
}
