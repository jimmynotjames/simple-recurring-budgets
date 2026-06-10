import Foundation
@testable import simple_recurring_budgets
import Testing

/// Tests for the `PersistenceError.init(operation:underlying:)` bridging
/// initializer: it must extract only the `NSError` domain and code (never user
/// data) so the value stays safe for `privacy: .public` logging and the
/// `persistence_save_failed` analytics event.
@Suite("PersistenceError underlying-error bridging")
struct PersistenceErrorTests {
  @Test func bridgesNSErrorDomainAndCode() {
    let underlying = NSError(domain: NSCocoaErrorDomain, code: 134_060, userInfo: [
      NSLocalizedDescriptionKey: "sensitive detail that must not be captured",
    ])

    let error = PersistenceError(operation: .budgetCreate, underlying: underlying)

    #expect(error.operation == .budgetCreate)
    #expect(error.errorDomain == NSCocoaErrorDomain)
    #expect(error.errorCode == 134_060)
  }

  @Test func bridgesSwiftErrorViaNSErrorBridge() {
    struct FakeSaveFailure: Error {}
    let underlying = FakeSaveFailure()
    let ns = underlying as NSError

    let error = PersistenceError(operation: .expenseDelete, underlying: underlying)

    #expect(error.operation == .expenseDelete)
    #expect(error.errorDomain == ns.domain)
    #expect(error.errorCode == ns.code)
  }

  @Test func equalDomainCodeAndOperation_areEqualAndHashAlike() {
    let first = PersistenceError(operation: .reorder, errorDomain: "d", errorCode: 7)
    let second = PersistenceError(operation: .reorder, errorDomain: "d", errorCode: 7)
    #expect(first == second)
    #expect(first.hashValue == second.hashValue)
  }
}
