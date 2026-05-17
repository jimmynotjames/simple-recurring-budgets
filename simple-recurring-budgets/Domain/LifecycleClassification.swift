import Foundation

/// Returns `true` when the period `[periodStart, periodEnd)` is active (not paused).
///
/// Pause and Resume operate at whole-period granularity per algorithm doc §A.5.4:
/// - A period that *contains* a pause or resume event is itself **active**.
/// - A period is **paused** only when no event falls within it AND the most recent
///   prior event was a pause.
/// - With no events the budget is always active.
///
/// **Contract:** `sortedLifecycleEvents` must be sorted ascending by
/// `(effectiveDate, lastModified)`. The walker hot path calls this once per period;
/// pre-sorting at the snapshot entry point lets this function early-terminate in a
/// single pass.
func isActive(
  periodStart: Date,
  periodEnd: Date,
  sortedLifecycleEvents: [LifecycleEvent]
) -> Bool {
  guard !sortedLifecycleEvents.isEmpty else { return true }

  // Single forward pass over the sorted array:
  // - track the latest event strictly before `periodStart` (`lastPrior`).
  // - return `true` immediately the first time an event lands in `[periodStart, periodEnd)`.
  // - break early once events go past `periodEnd` (the rest can't affect this period).
  var lastPrior: LifecycleEvent?
  for event in sortedLifecycleEvents {
    if event.effectiveDate >= periodEnd { break }
    if event.effectiveDate >= periodStart { return true }
    lastPrior = event
  }
  return lastPrior.map { $0.kind == .resume } ?? true
}

/// Returns `true` when the budget is currently paused **from a UI perspective** at `now`.
///
/// This is the moment-granular companion to `isActive(...)`: where `isActive` operates at
/// whole-period granularity for carry-over math (the pause-action period is itself active
/// for accrual), this function flips the UI state the instant a `.pause` event's
/// `effectiveDate` is reached. The two classifiers consume the same `LifecycleEvent`
/// source of truth but answer different questions:
///
/// - `isActive(...)` → "does this period contribute allocation to the carry-over walker?"
/// - `isPausedAtMoment(...)` → "should the UI show this budget as paused right now?"
///
/// The view layer reads `BudgetSnapshot.lifecycleState`, which is populated from this
/// classifier; the walker continues to use `isActive(...)`.
///
/// **Contract:** `sortedLifecycleEvents` must be sorted ascending by
/// `(effectiveDate, lastModified)`. With ties, later `lastModified` wins (matches
/// `isActive`'s sort key).
///
/// **Boundary:** the comparison is strict (`effectiveDate < now`). At the exact moment
/// of a pause event, the period is still treated as active — matching the math classifier
/// (which considers the pause-action period active) and preserving the date-picker upper
/// bound as a valid choice. In production, `now` is always strictly greater than any
/// just-recorded `effectiveDate` (snapshot's `Date()` runs strictly after the service's),
/// so the strict boundary is observationally equivalent to `<=`.
func isPausedAtMoment(
  now: Date,
  sortedLifecycleEvents: [LifecycleEvent]
) -> Bool {
  // Scan forward; the last event with effectiveDate < now wins.
  // Break early once an event's effectiveDate reaches or exceeds now.
  var latestApplicable: LifecycleEvent?
  for event in sortedLifecycleEvents {
    if event.effectiveDate >= now { break }
    latestApplicable = event
  }
  return latestApplicable?.kind == .pause
}
