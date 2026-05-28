import Foundation

/// Identifier for every production `context.save()` call site, used by the
/// shared persistence-save helper to attribute failures in logs and analytics.
///
/// Raw values are static `snake_case` literals and are written to:
/// - `Logger.persistence.error` interpolations (`privacy: .public`), and
/// - the `persistence_save_failed` analytics event's `operation` property
///   (the allow-list in `docs/analytics-spec.md` §5/§10).
///
/// Adding a new case requires registering the operation in `docs/analytics-spec.md`
/// and adding/modifying the matching write-path requirement under the
/// `persistence-error-handling` capability.
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

/// The error thrown by the shared persistence-save helper when `context.save()`
/// fails. Carries only the operation identifier and the underlying `NSError`'s
/// domain and code — never user data — so it is safe to log at `privacy: .public`
/// and to transmit via the `persistence_save_failed` analytics event.
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
