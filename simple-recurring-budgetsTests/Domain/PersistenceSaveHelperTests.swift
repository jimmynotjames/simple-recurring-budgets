import Foundation
@testable import simple_recurring_budgets
import SwiftData
import Testing

// MARK: - Helper container

@MainActor
private func makeInMemoryContext() throws -> ModelContext {
  let schema = Schema([Budget.self, ExpenseItem.self, AllocationChange.self, LifecycleEvent.self])
  let config = ModelConfiguration(isStoredInMemoryOnly: true)
  let container = try ModelContainer(for: schema, configurations: [config])
  return ModelContext(container)
}

// MARK: - Happy path

@Suite("ModelContext.saveChanges — success")
@MainActor
struct PersistenceSaveHelperSuccessTests {
  @Test("Successful save is silent: no analytics event fired")
  func successPathIsSilent() throws {
    let ctx = try makeInMemoryContext()
    let spy = SpyAnalyticsClient()

    // Insert a valid Budget and save. saveChanges should return without
    // throwing, log nothing on the persistence channel, and emit no analytics.
    let budget = Budget(period: .daily, isCarryOverEnabled: false)
    ctx.insert(budget)

    try ctx.saveChanges(operation: .budgetCreate, analytics: spy)

    #expect(spy.trackCalls.isEmpty, "Successful save must not emit persistence_save_failed")
  }
}

// MARK: - Failure path via the internal seam

@Suite("PersistenceSaveSurface.report — failure mapping & sibling boundary")
@MainActor
struct PersistenceSaveSurfaceFailureTests {
  private func syntheticError(domain: String = "TestDomain", code: Int = 42) -> NSError {
    NSError(
      domain: domain,
      code: code,
      userInfo: [NSLocalizedDescriptionKey: "synthetic-failure"]
    )
  }

  @Test("Failure rethrows PersistenceError with the right operation/domain/code")
  func failureMapsToPersistenceError() {
    let spy = SpyAnalyticsClient()
    let err = syntheticError(domain: "NSCocoaErrorDomain", code: 134_030)

    let mapped = PersistenceSaveSurface.report(
      operation: .expenseCreate,
      analytics: spy,
      error: err
    )

    #expect(mapped.operation == .expenseCreate)
    #expect(mapped.errorDomain == "NSCocoaErrorDomain")
    #expect(mapped.errorCode == 134_030)
  }

  @Test("Failure fires exactly one persistence_save_failed analytics event")
  func failureFiresOneAnalyticsEvent() {
    let spy = SpyAnalyticsClient()
    let err = syntheticError(domain: "NSCocoaErrorDomain", code: 134_030)

    _ = PersistenceSaveSurface.report(
      operation: .budgetEdit,
      analytics: spy,
      error: err
    )

    #expect(spy.trackCalls.count == 1)
    let call = spy.trackCalls[0]
    #expect(call.event == AnalyticsEvent.persistenceSaveFailed)
    #expect(call.properties?["operation"] == "budget_edit")
    #expect(call.properties?["error_domain"] == "NSCocoaErrorDomain")
    #expect(call.properties?["error_code"] == "134030")
  }

  @Test("Nil analytics client still logs and rethrows (no crash)")
  func nilAnalyticsStillWorks() {
    let err = syntheticError()
    let mapped = PersistenceSaveSurface.report(
      operation: .appLaunchDedup,
      analytics: nil,
      error: err
    )
    #expect(mapped.operation == .appLaunchDedup)
    #expect(mapped.errorDomain == "TestDomain")
    #expect(mapped.errorCode == 42)
  }

  @Test("Sibling boundary: analytics payload contains no user data fields")
  func siblingPayloadAllowList() {
    let spy = SpyAnalyticsClient()
    _ = PersistenceSaveSurface.report(
      operation: .expenseDelete,
      analytics: spy,
      error: syntheticError()
    )

    let props = spy.trackCalls[0].properties ?? [:]
    let allowedKeys: Set = ["operation", "error_domain", "error_code"]
    let actualKeys = Set(props.keys)
    #expect(
      actualKeys == allowedKeys,
      "persistence_save_failed payload must contain only operation/error_domain/error_code; got \(actualKeys.sorted())"
    )
  }
}
