import Foundation
@testable import simple_recurring_budgets
import SwiftData
import Testing

@MainActor
private func makeInMemoryContainer() throws -> ModelContainer {
  let schema = Schema([Budget.self, ExpenseItem.self, AllocationChange.self, LifecycleEvent.self])
  let config = ModelConfiguration(isStoredInMemoryOnly: true)
  return try ModelContainer(for: schema, configurations: [config])
}

@Suite("AppStartup — container-creation recovery")
@MainActor
struct AppStartupTests {
  @Test("Successful first attempt populates container and clears error")
  func successFirstAttempt() throws {
    let container = try makeInMemoryContainer()
    let startup = AppStartup(makeContainer: { (container, .localFallback) })

    #expect(startup.container === container)
    #expect(startup.containerBacking == .localFallback)
    #expect(startup.error == nil)
  }

  @Test("Failed first attempt populates typed error and leaves container nil")
  func failedFirstAttempt() {
    let underlying = NSError(domain: "NSCocoaErrorDomain", code: 134_030)
    let startup = AppStartup(makeContainer: { throw underlying })

    #expect(startup.container == nil)
    #expect(startup.containerBacking == nil)
    #expect(startup.error?.errorDomain == "NSCocoaErrorDomain")
    #expect(startup.error?.errorCode == 134_030)
  }

  @Test("Successful retry clears the error and populates container")
  func successfulRetry() throws {
    let container = try makeInMemoryContainer()
    var attempts = 0
    let startup = AppStartup(makeContainer: {
      attempts += 1
      if attempts == 1 {
        throw NSError(domain: "NSCocoaErrorDomain", code: 134_030)
      }
      return (container, .cloudKit)
    })

    #expect(startup.error != nil)
    #expect(startup.container == nil)

    startup.retry()

    #expect(startup.container === container)
    #expect(startup.containerBacking == .cloudKit)
    #expect(startup.error == nil)
    #expect(attempts == 2)
  }

  @Test("Failed retry refreshes the error and does not crash")
  func failedRetryUpdatesError() {
    var attempts = 0
    let startup = AppStartup(makeContainer: {
      attempts += 1
      let code = attempts == 1 ? 1 : 2
      throw NSError(domain: "TestDomain", code: code)
    })
    #expect(startup.error?.errorCode == 1)

    startup.retry()

    #expect(startup.container == nil)
    #expect(startup.containerBacking == nil)
    #expect(startup.error?.errorDomain == "TestDomain")
    #expect(startup.error?.errorCode == 2)
    #expect(attempts == 2)
  }
}
