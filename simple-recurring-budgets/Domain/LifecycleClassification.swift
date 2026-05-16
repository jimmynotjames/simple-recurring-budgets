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
