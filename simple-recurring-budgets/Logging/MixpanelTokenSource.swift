/// Exposes the Mixpanel project token for the active build configuration, read from Info.plist (injected
/// via `config/Secrets.xcconfig`).
///
/// `isConfigured` guards SDK initialization: while tokens are still the committed placeholder sentinels
/// (fresh clone without a local secrets file) the app uses `ConsoleAnalyticsClient`, with no Mixpanel
/// traffic and no crash. See `simple_recurring_budgetsApp.init()`.
///
/// Keep the `// gitleaks:allow` tags and `.gitleaksignore` fingerprints: they keep the full-history CI
/// secrets scan green for old commits that contained hardcoded tokens.
enum MixpanelTokenSource {
  // MARK: - Public

  /// `true` when both dev and prod tokens are real (non-placeholder), i.e. `config/Secrets.local.xcconfig` is
  /// present and filled. Pure function via `isConfigured(dev:prod:)` so tests stay environment-independent.
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
