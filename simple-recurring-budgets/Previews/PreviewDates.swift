#if DEBUG
  import Foundation

  /// Shared anchor dates for previews of inactive-state UI (`BudgetInactiveReason` variants), anchored off
  /// `Date()` at module load. Co-located so the `BudgetRemainingSummary`, `StatusChipRow`, and
  /// `InactiveStatusChip` previews see the same offsets. Not used by production code; `#if DEBUG` like the
  /// other preview support files.
  enum PreviewDates {
    /// Two weeks in the future — drives the `.preStart` chip preview ("Starts {date}").
    static let preStart: Date = Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()

    /// Two weeks ago — drives the `.paused` chip preview ("Paused · {date}").
    static let pausedSince: Date = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()

    /// One week ago — drives the `.postEnd` chip preview ("Ended {date}").
    static let postEnd: Date = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()

    /// ~2-month forward window — drives the long Specific Dates label preview that
    /// exercises the `ViewThatFits` H→V fallback at large Dynamic Type.
    static let specificDatesStart: Date = .init()
    static let specificDatesEnd: Date = Calendar.current.date(byAdding: .day, value: 58, to: Date()) ?? Date()
  }
#endif
