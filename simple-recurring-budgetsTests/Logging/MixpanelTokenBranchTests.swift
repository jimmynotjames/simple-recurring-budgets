@testable import simple_recurring_budgets
import Testing

/// §18.1 test contract #10 — DEBUG vs Release token literal is non-empty and the
/// two literals are distinct.
///
/// Since `simple_recurring_budgetsApp.init()` uses `#if DEBUG` to select the token,
/// we expose a testable helper function that returns the active token for the current
/// build configuration.
@Suite("Mixpanel token branch — §18.1 #10")
struct MixpanelTokenBranchTests {
  @Test("active Mixpanel token is non-empty")
  func activeTokenNonEmpty() {
    #expect(!MixpanelTokenSource.activeToken.isEmpty)
  }

  @Test("dev and prod tokens are distinct")
  func devAndProdTokensDistinct() {
    #expect(MixpanelTokenSource.devToken != MixpanelTokenSource.prodToken)
  }

  @Test("dev and prod tokens are both non-empty")
  func bothTokensNonEmpty() {
    #expect(!MixpanelTokenSource.devToken.isEmpty)
    #expect(!MixpanelTokenSource.prodToken.isEmpty)
  }
}
