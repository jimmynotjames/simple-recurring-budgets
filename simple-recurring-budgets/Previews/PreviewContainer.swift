#if DEBUG
  import Foundation
  import SwiftData

  /// Shared factory for in-memory `ModelContainer` instances used by every `#Preview`.
  ///
  /// Mirrors `TestModelContainer` (which lives in the tests target under `@testable import`)
  /// so that preview code can share the same in-memory, CloudKit-disabled setup without
  /// depending on the test target. Seeds the container with the canonical fixtures from
  /// `DebugData` so previews always render against a representative dataset.
  ///
  /// Use from any screen preview:
  ///
  /// ```swift
  /// #Preview {
  ///     RootView()
  ///         .modelContainer(PreviewContainer.make())
  ///         .environment(Router())
  ///         .environment(AppSettings())
  /// }
  /// ```
  ///
  /// Keep all preview containers going through this single entry point so we don't end up
  /// with five slightly different preview setups scattered across screens.
  enum PreviewContainer {
    /// Creates an isolated in-memory `ModelContainer` with CloudKit disabled and seeds it
    /// with every fixture from `DebugData`.
    ///
    /// - Parameter now: The anchor date used by `DebugData` to place relative expense dates.
    ///   Defaults to the current wall-clock `Date()`; pass a fixed value for deterministic
    ///   snapshots.
    static func make(now: Date = Date()) -> ModelContainer {
      InMemoryModelContainer.makeSeeded(now: now)
    }
  }
#endif
