import Foundation

/// Identifier for every production `context.save()` call site, used by the shared save helper to attribute
/// failures in logs and analytics.
///
/// Raw values are static `snake_case` literals written to `Logger.persistence.error` (`privacy: .public`)
/// and the `persistence_save_failed` event's `operation` property (allow-list in `docs/analytics-spec.md`).
///
/// A new case must be registered in `docs/analytics-spec.md` and covered by the matching write-path
/// requirement under `persistence-error-handling`.
enum PersistenceOperation: String, Hashable {
  case budgetCreate = "budget_create"
  case budgetEdit = "budget_edit"
  case budgetDelete = "budget_delete"
  case expenseCreate = "expense_create"
  case expenseEdit = "expense_edit"
  case expenseDelete = "expense_delete"
  case reorder
  case lifecyclePause = "lifecycle_pause"
  case lifecycleResume = "lifecycle_resume"
  case lifecycleAllocationEdit = "lifecycle_allocation_edit"
  case lifecycleResetCarryOver = "lifecycle_reset_carry_over"
  case lifecycleResetBudget = "lifecycle_reset_budget"
  case lifecycleRollover = "lifecycle_rollover"
  case appLaunchDedup = "app_launch_dedup"
}

/// Thrown by the shared save helper when `context.save()` fails. Carries only the operation and the
/// underlying `NSError`'s domain and code, never user data, so it is safe to log at `privacy: .public` and
/// send in `persistence_save_failed`.
struct PersistenceError: Error, Hashable {
  let operation: PersistenceOperation
  let errorDomain: String
  let errorCode: Int

  init(operation: PersistenceOperation, errorDomain: String, errorCode: Int) {
    self.operation = operation
    self.errorDomain = errorDomain
    self.errorCode = errorCode
  }

  /// Extract domain/code from an arbitrary `Error` by bridging through `NSError`.
  init(operation: PersistenceOperation, underlying: any Error) {
    let ns = underlying as NSError
    self.operation = operation
    errorDomain = ns.domain
    errorCode = ns.code
  }
}
