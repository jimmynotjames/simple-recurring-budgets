/// Exposes the Mixpanel project token literals for testability.
///
/// Both build configurations use `MixpanelAnalyticsClient` (§8 analytics-spec.md).
/// Physical separation of dev/prod data is enforced by the token, not by swapping
/// client classes. This helper lets test contract §18.1 #10 verify that the two
/// literals are distinct and non-empty without modifying the app entry.
enum MixpanelTokenSource {
  static let devToken = "d75149bc04193d5313f130cd688a54c9" // gitleaks:allow
  static let prodToken = "6d8492115467535089006f9ad413cb94" // gitleaks:allow

  static var activeToken: String {
    #if DEBUG
      devToken
    #else
      prodToken
    #endif
  }
}
