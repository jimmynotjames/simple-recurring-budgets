@testable import simple_recurring_budgets
import Testing

/// §18.1 test contract #10 — Token source selection and `isConfigured` logic.
///
/// All tests are env-independent: they inject tokens directly into
/// `MixpanelTokenSource.isConfigured(dev:prod:)` rather than reading
/// `Bundle.main`, so results are deterministic regardless of whether
/// `Config/Secrets.local.xcconfig` is present.
@Suite("Mixpanel token branch — §18.1 #10")
struct MixpanelTokenBranchTests {
  // MARK: - isConfigured pure-function tests

  @Test("isConfigured returns true for two non-placeholder non-empty tokens")
  func isConfiguredWithRealTokens() {
    #expect(
      MixpanelTokenSource.isConfigured(
        dev: "d75149bc04193d5313f130cd688a549",
        prod: "6d8492115467535089006f9ad413cb9"
      )
    )
  }

  @Test("isConfigured returns false when dev token is the placeholder sentinel")
  func isConfiguredFalseForPlaceholderDev() {
    #expect(
      !MixpanelTokenSource.isConfigured(
        dev: AppConfig.Placeholder.mixpanelDevToken,
        prod: "6d8492115467535089006f9ad413cb9"
      )
    )
  }

  @Test("isConfigured returns false when prod token is the placeholder sentinel")
  func isConfiguredFalseForPlaceholderProd() {
    #expect(
      !MixpanelTokenSource.isConfigured(
        dev: "d75149bc04193d5313f130cd688a549",
        prod: AppConfig.Placeholder.mixpanelProdToken
      )
    )
  }

  @Test("isConfigured returns false when both tokens are placeholders")
  func isConfiguredFalseForBothPlaceholders() {
    #expect(
      !MixpanelTokenSource.isConfigured(
        dev: AppConfig.Placeholder.mixpanelDevToken,
        prod: AppConfig.Placeholder.mixpanelProdToken
      )
    )
  }

  @Test("isConfigured returns false when dev token is empty")
  func isConfiguredFalseForEmptyDev() {
    #expect(
      !MixpanelTokenSource.isConfigured(
        dev: "",
        prod: "6d8492115467535089006f9ad413cb9"
      )
    )
  }

  @Test("isConfigured returns false when prod token is empty")
  func isConfiguredFalseForEmptyProd() {
    #expect(
      !MixpanelTokenSource.isConfigured(
        dev: "d75149bc04193d5313f130cd688a549",
        prod: ""
      )
    )
  }

  // MARK: - Sentinel-sync tests (AppConfig.Placeholder values mirror Secrets.xcconfig)

  @Test("Dev placeholder sentinel matches expected value in Secrets.xcconfig")
  func devPlaceholderSentinelValue() {
    #expect(AppConfig.Placeholder.mixpanelDevToken == "PLACEHOLDER_MIXPANEL_DEV_TOKEN")
  }

  @Test("Prod placeholder sentinel matches expected value in Secrets.xcconfig")
  func prodPlaceholderSentinelValue() {
    #expect(AppConfig.Placeholder.mixpanelProdToken == "PLACEHOLDER_MIXPANEL_PROD_TOKEN")
  }

  @Test("Dev and prod placeholder sentinels are distinct from each other")
  func placeholderSentinelsAreDistinct() {
    #expect(AppConfig.Placeholder.mixpanelDevToken != AppConfig.Placeholder.mixpanelProdToken)
  }

  @Test("Placeholder sentinels are non-empty")
  func placeholderSentinelsNonEmpty() {
    #expect(!AppConfig.Placeholder.mixpanelDevToken.isEmpty)
    #expect(!AppConfig.Placeholder.mixpanelProdToken.isEmpty)
  }
}
