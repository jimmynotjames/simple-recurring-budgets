import Foundation
import OSLog
import SwiftData

extension ModelContext {
  /// Shared persistence-save helper. Every production `context.save()` call
  /// site routes through this method instead of `try? context.save()`.
  ///
  /// On success the helper returns silently. On failure it:
  /// 1. Emits **one** `Logger.persistence.error` line (sibling diagnostic).
  /// 2. Fires **one** `persistence_save_failed` analytics event (sibling).
  /// 3. Rethrows a `PersistenceError` carrying the operation identifier and
  ///    the underlying `NSError`'s domain and code.
  ///
  /// ### Boundary note (diagnostic-logging spec)
  ///
  /// The `Logger.persistence.error` call and the `analytics.track(...)` call
  /// are **sibling** statements built from the same plain values
  /// (`operation.rawValue`, `error_domain`, `error_code`). Neither call
  /// consumes the other's return value, and no `OSLog`-shaped type ever
  /// crosses into `AnalyticsClient` — this is the "Sibling call sites are
  /// allowed" case in the `diagnostic-logging` boundary requirement, made
  /// explicit by the "Save-failure log and analytics event are sibling, not
  /// cross-routed" scenario.
  ///
  /// - Parameters:
  ///   - operation: The originating call site (used in log + analytics).
  ///   - analytics: The active `AnalyticsClient`. Pass `nil` from contexts
  ///     where no analytics client is available (e.g. early bootstrap before
  ///     consent is resolved); failures will still log.
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

/// Internal seam exposing the helper's log + track + map-to-`PersistenceError`
/// logic without requiring a real `ModelContext.save()` to throw. Tests pass
/// a synthetic `NSError`; production calls it from inside the extension's
/// `catch`. Keeps the boundary contract (one log line, one analytics event,
/// rethrown `PersistenceError`) in one place.
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
