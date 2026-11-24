import Foundation
import Observation
import SwiftData

/// Typed failure from container creation: only the underlying `NSError`'s `domain` and `code`, never user
/// data, so it is safe to log at `privacy: .public` and include in the feedback mailto body.
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

/// Launch-time container-creation result. The `@main` App branches on `container`: success hosts
/// `RootView`; failure hosts `ContainerFailureView`, whose **Retry** calls `retry()`.
///
/// `makeContainer` is injected so tests can drive failure/retry without `ProductionContainerFactory.make`.
@Observable @MainActor
final class AppStartup {
  /// The live container on success; `nil` while the failure surface is shown.
  private(set) var container: ModelContainer?
  /// The resolved backing on success; `nil` on failure.
  private(set) var containerBacking: SyncStatus.ContainerBacking?
  /// The typed failure when both creation paths threw; `nil` on success.
  private(set) var error: ContainerCreationFailure?

  /// Injected for testability; production wraps `ProductionContainerFactory.make`.
  private let makeContainer: @MainActor () throws -> (ModelContainer, SyncStatus.ContainerBacking)

  init(makeContainer: @escaping @MainActor () throws -> (ModelContainer, SyncStatus.ContainerBacking)) {
    self.makeContainer = makeContainer
    attempt()
  }

  /// Re-runs `makeContainer`; called by **Retry** in `ContainerFailureView`. Success clears `error` and sets
  /// `container` + `containerBacking`; failure refreshes `error`.
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
