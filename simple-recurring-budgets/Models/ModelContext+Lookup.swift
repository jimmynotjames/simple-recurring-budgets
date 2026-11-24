import Foundation
import SwiftData

/// UUID-based model lookups for route resolution. `AppRoute` / `SheetRoute` carry stable `UUID`s, and
/// `RootView` resolves them here at the destination. `nil` means the model no longer exists (typically
/// deleted on another device after the route was pushed); the caller should dismiss the route.
extension ModelContext {
  /// Resolves a `Budget` by its stable `id`. Returns `nil` when no match exists.
  func budget(id: UUID) -> Budget? {
    var descriptor = FetchDescriptor<Budget>(predicate: #Predicate { $0.id == id })
    descriptor.fetchLimit = 1
    return (try? fetch(descriptor))?.first
  }

  /// Resolves an `ExpenseItem` by its stable `id`. Returns `nil` when no match exists.
  func expenseItem(id: UUID) -> ExpenseItem? {
    var descriptor = FetchDescriptor<ExpenseItem>(predicate: #Predicate { $0.id == id })
    descriptor.fetchLimit = 1
    return (try? fetch(descriptor))?.first
  }
}
