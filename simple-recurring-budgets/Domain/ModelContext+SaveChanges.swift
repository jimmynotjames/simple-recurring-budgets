import Foundation
import OSLog
import SwiftData

extension ModelContext {
  /// Shared persistence-save helper; every production `context.save()` routes through it rather than
  /// `try? context.save()`.
  ///
  /// On failure it emits **one** `Logger.persistence.error` line, fires **one** `persistence_save_failed`
  /// analytics event, and rethrows a `PersistenceError` with the operation and the underlying `NSError`'s
  /// domain and code.
  ///
  /// The log and the `analytics.track(...)` call are **sibling** statements built from the same plain values
  /// (`operation.rawValue`, `error_domain`, `error_code`). Neither consumes the other's result and no
  /// `OSLog`-shaped type crosses into `AnalyticsClient`, as the `diagnostic-logging` boundary requires.
  ///
  /// - Parameters:
  ///   - operation: The originating call site (used in log + analytics).
  ///   - analytics: The active `AnalyticsClient`; pass `nil` where none exists (e.g. early bootstrap before
  ///     consent is resolved). Failures still log.
  func saveChanges(
    operation: PersistenceOperation,
    analytics: (any AnalyticsClient)? = nil
  ) throws {
    do {
      try save()
    } catch {
      throw PersistenceSaveSurface.report(
        operation: operation,
        analytics: analytics,
        error: error
      )
    }
  }
}

/// Internal seam exposing the log + track + map-to-`PersistenceError` logic without a real throwing
/// `ModelContext.save()`. Tests pass a synthetic `NSError`; production calls it from the extension's `catch`.
enum PersistenceSaveSurface {
  static func report(
    operation: PersistenceOperation,
    analytics: (any AnalyticsClient)?,
    error: any Error
  ) -> PersistenceError {
    let ns = error as NSError
    let domain = ns.domain
    let code = ns.code

    // Sibling 1 — diagnostic OSLog.
    Logger.persistence.error(
      "persistence.save.failed operation=\(operation.rawValue, privacy: .public) domain=\(domain, privacy: .public) code=\(code, privacy: .public) description=\(error.localizedDescription, privacy: .public)"
    )

    // Sibling 2 — product-analytics diagnostic event (consent-gated downstream).
    analytics?.track(
      AnalyticsEvent.persistenceSaveFailed,
      properties: [
        AnalyticsProperty.operation: operation.rawValue,
        AnalyticsProperty.errorDomain: domain,
        AnalyticsProperty.errorCode: code,
      ]
    )

    return PersistenceError(
      operation: operation,
      errorDomain: domain,
      errorCode: code
    )
  }
}
