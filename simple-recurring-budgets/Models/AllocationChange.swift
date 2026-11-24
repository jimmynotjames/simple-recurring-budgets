import Foundation
import SwiftData

/// A forward-only allocation change for a `Budget`: the per-period allocation in effect from `effectiveFrom`
/// onward. `lastModified` breaks `effectiveFrom` ties (later wins) so concurrent CloudKit edits converge.
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
