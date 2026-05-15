import Foundation

/// Returns `true` when the period `[periodStart, periodEnd)` is active (not paused).
///
/// Pause and Resume operate at whole-period granularity per algorithm doc §A.5.4:
/// - A period that *contains* a pause or resume event is itself **active**.
/// - A period is **paused** only when no event falls within it AND the most recent
///   prior event was a pause.
/// - With no events the budget is always active.
func isActive(
  periodStart: Date,
  periodEnd: Date,
  lifecycleEvents: [LifecycleEvent]
) -> Bool {
  guard !lifecycleEvents.isEmpty else { return true }

  let sorted = lifecycleEvents.sorted { $0.effectiveDate < $1.effectiveDate }

  // Any event that lands inside this period makes the period active (pause-action period
  // and resume-action period are both active by definition).
  let inPeriod = sorted.filter { $0.effectiveDate >= periodStart && $0.effectiveDate < periodEnd }
  if !inPeriod.isEmpty { return true }

  // No in-period event: use the state established by the most recent prior event.
  let prior = sorted.filter { $0.effectiveDate < periodStart }
  guard let lastPrior = prior.last else { return true } // no history → active
  return lastPrior.kind == .resume
}
