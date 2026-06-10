import Foundation
@testable import simple_recurring_budgets
import SwiftData
import Testing

/// Drives `ProductionContainerFactory.make` through injected container
/// factories (test-coverage-audit-2026-06-10 B1): the real `ModelContainer`
/// initializers cannot be made to fail deterministically, so the closures
/// substitute in-memory containers / thrown errors and record the
/// configurations they were offered. No test touches the on-disk store.
@Suite("ProductionContainerFactory — CloudKit→local branch selection")
@MainActor
struct ProductionContainerFactoryTests {
  /// Stand-in success container; in-memory so tests never write the real store.
  private func inMemoryContainer() throws -> ModelContainer {
    try TestModelContainer.make()
  }

  @Test("Cloud succeeds → .cloudKit backing, local factory never consulted")
  func cloudSuccess() throws {
    let stub = try inMemoryContainer()
    var localCalled = false

    let (container, backing) = try ProductionContainerFactory.make(
      cloud: { _ in stub },
      local: { _ in
        localCalled = true
        return stub
      }
    )

    #expect(container === stub)
    #expect(backing == .cloudKit)
    #expect(!localCalled, "local factory must not run when the CloudKit path succeeds")
  }

  @Test("Cloud fails, local succeeds → .localFallback backing")
  func cloudFailsLocalSucceeds() throws {
    let stub = try inMemoryContainer()

    let (container, backing) = try ProductionContainerFactory.make(
      cloud: { _ in throw NSError(domain: "CKErrorDomain", code: 9) },
      local: { _ in stub }
    )

    #expect(container === stub)
    #expect(backing == .localFallback)
  }

  @Test("Both fail → the local error propagates (AppStartup handoff)")
  func bothFail() {
    let localError = NSError(domain: "NSCocoaErrorDomain", code: 134_030)

    #expect {
      try ProductionContainerFactory.make(
        cloud: { _ in throw NSError(domain: "CKErrorDomain", code: 9) },
        local: { _ in throw localError }
      )
    } throws: { error in
      let nsError = error as NSError
      return nsError.domain == "NSCocoaErrorDomain" && nsError.code == 134_030
    }
  }

  @Test("Cloud and local configurations share one on-disk store URL (issue #1)")
  func sharedStoreURL() throws {
    let stub = try inMemoryContainer()
    var cloudURL: URL?
    var localURL: URL?

    _ = try ProductionContainerFactory.make(
      cloud: { config in
        cloudURL = config.url
        throw NSError(domain: "CKErrorDomain", code: 9)
      },
      local: { config in
        localURL = config.url
        return stub
      }
    )

    #expect(cloudURL != nil)
    #expect(
      cloudURL == localURL,
      "both configurations must anchor to the same store URL or an offline-first launch forks the store"
    )
  }
}
