import Foundation

/// Returns `true` when the period `[periodStart, periodEnd)` is active (not paused).
///
/// Pause and resume apply per whole period:
/// - A period that contains a pause or resume event is active.
/// - Otherwise it is paused only if the most recent earlier event was a pause.
/// - With no events the budget is always active.
///
/// `sortedLifecycleEvents` must be sorted ascending by `(effectiveDate, lastModified)`.
/// The walker calls this once per period, so the pre-sort lets it stop early.
func isActive(
  periodStart: Date,
  periodEnd: Date,
  sortedLifecycleEvents: [LifecycleEvent]
) -> Bool {
  guard !sortedLifecycleEvents.isEmpty else { return true }

  var lastPrior: LifecycleEvent?
  for event in sortedLifecycleEvents {
    if event.effectiveDate >= periodEnd {
      break
    }
    if event.effectiveDate >= periodStart {
      return true
    }
    lastPrior = event
  }
  return lastPrior.map { $0.kind == .resume } ?? true
}

/// Returns `true` when the UI should show the budget as paused at `now`.
///
/// Unlike `isActive(...)`, which decides whether a whole period accrues allocation for
/// carry-over, this flips the moment a `.pause` event's `effectiveDate` passes. Views read
/// it via `BudgetSnapshot.lifecycleState`; the carry-over walker uses `isActive(...)`.
///
/// `sortedLifecycleEvents` must be sorted ascending by `(effectiveDate, lastModified)`, so
/// on ties the later `lastModified` wins.
///
/// The comparison is deliberately strict (`effectiveDate < now`): at the exact pause
/// instant the budget still reads as active, matching `isActive` and keeping the
/// date picker's upper bound a valid choice. Don't change it to `<=`.
func isPausedAtMoment(
  now: Date,
  sortedLifecycleEvents: [LifecycleEvent]
) -> Bool {
  var latestApplicable: LifecycleEvent?
  for event in sortedLifecycleEvents {
    if event.effectiveDate >= now {
      break
    }
    latestApplicable = event
  }
  return latestApplicable?.kind == .pause
}
