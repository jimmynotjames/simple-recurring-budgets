#if DEBUG
  import Foundation
  import SwiftData

  /// Shared factory for the in-memory, CloudKit-disabled `ModelContainer` used by every `#Preview`, seeded
  /// with the canonical `DebugData` fixtures. Mirrors `TestModelContainer` (tests target) so previews don't
  /// depend on the test target.
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
  /// Route all preview containers through this single entry point.
  enum PreviewContainer {
    /// Creates an isolated in-memory `ModelContainer` with CloudKit disabled, seeded with every `DebugData` fixture.
    ///
    /// - Parameter now: Anchor date for `DebugData`'s relative expense dates; pass a fixed value for
    ///   deterministic snapshots.
    static func make(now: Date = Date()) -> ModelContainer {
      InMemoryModelContainer.makeSeeded(now: now)
    }
  }
#endif
