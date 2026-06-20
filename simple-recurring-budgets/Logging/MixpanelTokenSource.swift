/// Exposes the Mixpanel project token for the active build configuration,
/// read from Info.plist (injected via `config/Secrets.xcconfig`).
///
/// `isConfigured` guards SDK initialization: when tokens are still the
/// committed placeholder sentinels (fresh clone without a local secrets
/// file), the app falls back to `ConsoleAnalyticsClient` — no Mixpanel
/// traffic, no crash. See `simple_recurring_budgetsApp.init()`.
///
/// Token source moved from hardcoded literals to xcconfig/Info.plist in the
/// `public-repo-secrets-and-license` change; `// gitleaks:allow` tags and
/// `.gitleaksignore` fingerprints are retained to keep the full-history CI
/// scan green (those commits are not rewritten).
enum MixpanelTokenSource {
  // MARK: - Public

  /// `true` when both dev and prod tokens are real (non-placeholder) values,
  /// indicating `config/Secrets.local.xcconfig` is present and filled.
  ///
  /// Exposed as a testable pure function via `isConfigured(dev:prod:)`.
  static var isConfigured: Bool {
    isConfigured(dev: AppConfig.mixpanelDevToken, prod: AppConfig.mixpanelProdToken)
  }

  /// Pure-function form of `isConfigured` — takes injected strings so tests
  /// don't touch `Bundle.main` and remain environment-independent.
  static func isConfigured(dev: String, prod: String) -> Bool {
    !dev.isEmpty
      && !prod.isEmpty
      && dev != AppConfig.Placeholder.mixpanelDevToken
      && prod != AppConfig.Placeholder.mixpanelProdToken
  }

  /// Token for the active build configuration.
  /// Debug builds use the dev token; Release builds use the prod token.
  static var activeToken: String {
    #if DEBUG
      AppConfig.mixpanelDevToken
    #else
      AppConfig.mixpanelProdToken
    #endif
  }
}
