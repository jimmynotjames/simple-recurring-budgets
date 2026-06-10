import Foundation
@testable import simple_recurring_budgets
import Testing

@Suite("SaveErrorState — 3-strikes rule")
@MainActor
struct SaveErrorStateTests {
  private func makeError(
    operation: PersistenceOperation = .budgetCreate,
    domain: String = "TestDomain",
    code: Int = 1
  ) -> PersistenceError {
    PersistenceError(operation: operation, errorDomain: domain, errorCode: code)
  }

  @Test("First failure starts the count at 1 and does not yet offer Send Feedback")
  func firstFailureCountIsOne() {
    var state: SaveErrorState?
    state.setForFailure(makeError(), retry: {})

    #expect(state?.consecutiveFailureCount == 1)
    #expect(state?.shouldOfferFeedback == false)
  }

  @Test("Two consecutive failures of the same operation increment the count")
  func twoConsecutiveFailuresIncrement() {
    var state: SaveErrorState?
    state.setForFailure(makeError(), retry: {})
    state.setForFailure(makeError(), retry: {})

    #expect(state?.consecutiveFailureCount == 2)
    #expect(state?.shouldOfferFeedback == false)
  }

  @Test("Third consecutive failure flips shouldOfferFeedback true")
  func thirdFailureEscalates() {
    var state: SaveErrorState?
    state.setForFailure(makeError(), retry: {})
    state.setForFailure(makeError(), retry: {})
    state.setForFailure(makeError(), retry: {})

    #expect(state?.consecutiveFailureCount == 3)
    #expect(state?.shouldOfferFeedback == true)
  }

  @Test("Switching operation resets the count to 1")
  func operationChangeResets() {
    var state: SaveErrorState?
    state.setForFailure(makeError(operation: .budgetCreate), retry: {})
    state.setForFailure(makeError(operation: .budgetCreate), retry: {})
    state.setForFailure(makeError(operation: .expenseDelete), retry: {})

    #expect(state?.operation == .expenseDelete)
    #expect(state?.consecutiveFailureCount == 1)
    #expect(state?.shouldOfferFeedback == false)
  }

  @Test("clear() drops the state so the next failure starts at 1")
  func clearResets() {
    var state: SaveErrorState?
    state.setForFailure(makeError(), retry: {})
    state.setForFailure(makeError(), retry: {})
    state.clear()

    #expect(state == nil)

    state.setForFailure(makeError(), retry: {})
    #expect(state?.consecutiveFailureCount == 1)
    #expect(state?.shouldOfferFeedback == false)
  }

  @Test("Feedback mailto carries only operation + error domain/code (no user data)")
  func feedbackMailtoIsAllowListed() {
    let url = FeedbackMailto.diagnosticURL(
      operation: .expenseEdit,
      errorDomain: "NSCocoaErrorDomain",
      errorCode: 134_030
    )
    let absolute = url.absoluteString

    // Must include the three allow-listed values (URL-encoded forms).
    #expect(absolute.contains("expense_edit"))
    #expect(absolute.contains("NSCocoaErrorDomain"))
    #expect(absolute.contains("134030"))

    // Must NOT include any forbidden field markers. (Sentinel strings unlikely to
    // appear in a clean mailto: but this guards against accidental leakage.)
    #expect(!absolute.lowercased().contains("budget_name"))
    #expect(!absolute.lowercased().contains("expense_name"))
    #expect(!absolute.lowercased().contains("amount"))
  }
}
