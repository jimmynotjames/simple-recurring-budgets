@testable import simple_recurring_budgets
import Testing

/// Fixture tests that guard the sentinel-sync contract:
/// `AppConfig.Placeholder` values must match the sentinel strings that
/// `scripts/verify_release_secrets.sh` checks. If these get out of sync,
/// the ship guard will fail to catch a placeholder build — a silent bug.
///
/// These tests do NOT touch `Bundle.main`; they only inspect the Swift constants.
@Suite("AppConfig sentinel sync — ship-guard contract")
struct AppConfigSentinelTests {
  // MARK: - Mixpanel sentinels (must match verify_release_secrets.sh)

  @Test("Dev token sentinel matches the string the ship guard checks")
  func mixpanelDevTokenSentinelMatchesShipGuard() {
    // verify_release_secrets.sh does NOT check the dev token (prod only matters for shipping).
    // This test exists to document the value and guard against an accidental change.
    #expect(AppConfig.Placeholder.mixpanelDevToken == "PLACEHOLDER_MIXPANEL_DEV_TOKEN")
  }

  @Test("Prod token sentinel matches the string the ship guard checks for MIXPANEL_PROD_TOKEN")
  func mixpanelProdTokenSentinelMatchesShipGuard() {
    // scripts/verify_release_secrets.sh checks:
    //   [[ "$MIXPANEL_PROD" == "PLACEHOLDER_MIXPANEL_PROD_TOKEN" ]]
    #expect(AppConfig.Placeholder.mixpanelProdToken == "PLACEHOLDER_MIXPANEL_PROD_TOKEN")
  }

  // MARK: - Feedback email sentinel (must match verify_release_secrets.sh)

  @Test("Feedback email sentinel matches the string the ship guard checks for FEEDBACK_EMAIL")
  func feedbackEmailSentinelMatchesShipGuard() {
    // scripts/verify_release_secrets.sh checks:
    //   [[ "$FEEDBACK" == "noreply@example.com" ]]
    #expect(AppConfig.Placeholder.feedbackEmail == "noreply@example.com")
  }

  // MARK: - Privacy URL sentinel (must match verify_release_secrets.sh)

  @Test("Privacy URL sentinel contains the host the ship guard checks")
  func privacyURLSentinelMatchesShipGuard() {
    // scripts/verify_release_secrets.sh checks:
    //   echo "$PRIVACY" | grep -q "example.com/privacy"
    #expect(AppConfig.Placeholder.privacyPolicyURL.contains("example.com/privacy"))
  }

  // MARK: - All sentinels are non-empty

  @Test("All AppConfig placeholder sentinels are non-empty strings")
  func allPlaceholderSentinelsNonEmpty() {
    #expect(!AppConfig.Placeholder.mixpanelDevToken.isEmpty)
    #expect(!AppConfig.Placeholder.mixpanelProdToken.isEmpty)
    #expect(!AppConfig.Placeholder.feedbackEmail.isEmpty)
    #expect(!AppConfig.Placeholder.privacyPolicyURL.isEmpty)
  }
}
