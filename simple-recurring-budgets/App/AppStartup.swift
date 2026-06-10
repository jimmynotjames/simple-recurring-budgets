import Foundation
import Observation
import SwiftData

/// Typed value carried by `AppStartup.error` when container creation fails.
///
/// Holds only the underlying `NSError`'s `domain` and `code` — never any user
/// data — so it is safe to log at `privacy: .public` and to transmit in the
/// container-failure feedback mailto body. Mirrors the `PersistenceError`
/// shape from the `persistence-error-handling` capability for consistency.
struct ContainerCreationFailure: Equatable, Hashable {
  let errorDomain: String
  let errorCode: Int

  init(errorDomain: String, errorCode: Int) {
    self.errorDomain = errorDomain
    self.errorCode = errorCode
  }

  /// Bridge through `NSError` to extract domain + code from any `Error`.
  init(underlying: any Error) {
    let ns = underlying as NSError
    errorDomain = ns.domain
    errorCode = ns.code
  }
}

/// Source-of-truth for app launch's container-creation result.
///
/// The `@main` App's body branches on `container`: success → host `RootView`
/// with `.modelContainer(container)`; failure → host `ContainerFailureView`,
/// which calls `retry()` from its **Retry** button.
///
/// `makeContainer` is injected so tests can drive the failure / retry paths
/// without going through `ProductionContainerFactory.make`.
@Observable @MainActor
final class AppStartup {
  /// The live container on the success path; `nil` while the failure surface
  /// is presented.
  private(set) var container: ModelContainer?
  /// The resolved backing on success; `nil` on failure.
  private(set) var containerBacking: SyncStatus.ContainerBacking?
  /// The typed failure when both creation paths threw; `nil` on success.
  private(set) var error: ContainerCreationFailure?

  /// Container-creation function, injected for testability. The production
  /// closure wraps `ProductionContainerFactory.make`.
  private let makeContainer: @MainActor () throws -> (ModelContainer, SyncStatus.ContainerBacking)

  init(makeContainer: @escaping @MainActor () throws -> (ModelContainer, SyncStatus.ContainerBacking)) {
    self.makeContainer = makeContainer
    attempt()
  }

  /// Re-runs `makeContainer` and updates state. Called by **Retry** in
  /// `ContainerFailureView`. A successful retry clears `error` and populates
  /// `container` + `containerBacking`; a failed retry refreshes `error`
  /// without crashing.
  func retry() {
    attempt()
  }

  private func attempt() {
    do {
      let (madeContainer, backing) = try makeContainer()
      container = madeContainer
      containerBacking = backing
      error = nil
    } catch let underlying {
      container = nil
      containerBacking = nil
      error = ContainerCreationFailure(underlying: underlying)
    }
  }
}
