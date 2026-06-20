import Foundation

/// Typed access to app configuration injected via Info.plist
/// (built from `config/Secrets.xcconfig` + the gitignored
/// `config/Secrets.local.xcconfig`).
///
/// All properties read from `Bundle.main` at the callsite — no caching.
/// Values fall back gracefully to their placeholder sentinels when the key
/// is absent (no fatalError). This guarantees a fresh clone without a local
/// secrets file launches without crashing.
///
/// Sentinel string constants must stay in sync with the default values in
/// `config/Secrets.xcconfig` and in `scripts/verify_release_secrets.sh`.
enum AppConfig {
  // MARK: - Sentinels (keep in sync with config/Secrets.xcconfig defaults)

  enum Placeholder {
    static let mixpanelDevToken = "PLACEHOLDER_MIXPANEL_DEV_TOKEN"
    static let mixpanelProdToken = "PLACEHOLDER_MIXPANEL_PROD_TOKEN"
    static let feedbackEmail = "noreply@example.com"
    static let privacyPolicyURL = "https://example.com/privacy"
  }

  // MARK: - Bundle reads

  static var mixpanelDevToken: String {
    Bundle.main.object(forInfoDictionaryKey: "MixpanelDevToken") as? String
      ?? Placeholder.mixpanelDevToken
  }

  static var mixpanelProdToken: String {
    Bundle.main.object(forInfoDictionaryKey: "MixpanelProdToken") as? String
      ?? Placeholder.mixpanelProdToken
  }

  static var feedbackEmail: String {
    Bundle.main.object(forInfoDictionaryKey: "FeedbackEmail") as? String
      ?? Placeholder.feedbackEmail
  }

  static var privacyPolicyURL: String {
    Bundle.main.object(forInfoDictionaryKey: "PrivacyPolicyURL") as? String
      ?? Placeholder.privacyPolicyURL
  }
}
