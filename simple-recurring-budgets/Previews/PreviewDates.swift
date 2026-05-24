#if DEBUG
  import Foundation

  /// Shared anchor dates for SwiftUI previews of inactive-state UI (`BudgetInactiveReason`
  /// variants). Anchored off `Date()` at module load — same staleness behavior as the
  /// per-file constants these replace, but co-located so the three offsets stay in sync
  /// and the call sites in `BudgetRemainingSummary`, `StatusChipRow`, and
  /// `InactiveStatusChip` all see the same values.
  ///
  /// Not used by production code. The `#if DEBUG` gate matches the existing pattern in
  /// `BudgetDetailFixtures.swift` / `PreviewContainer.swift`.
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
