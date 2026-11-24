import Foundation

/// Classifies a device's region as requiring explicit opt-in consent for product analytics, or permitting
/// auto opt-in. Region codes come from `Locale.current.region?.identifier` at call time. The table below
/// mirrors `docs/analytics-spec.md` §7.2; update both together.
enum ConsentJurisdiction: Equatable {
  /// Analytics require explicit, affirmative opt-in before any event may be sent.
  case required

  /// Analytics are default-on; the user may opt out at any time via the Settings toggle.
  case autoOptin

  nonisolated static func == (lhs: ConsentJurisdiction, rhs: ConsentJurisdiction) -> Bool {
    switch (lhs, rhs) {
    case (.required, .required), (.autoOptin, .autoOptin): true
    default: false
    }
  }

  // MARK: - Lookup

  /// Returns the jurisdiction kind for a `Locale.Region` identifier. Callers pass
  /// `Locale.current.region?.identifier` so this stays pure. `regionIdentifier` is an ISO 3166-1 alpha-2 code
  /// (e.g. `"DE"`, `"US"`); `nil` (region unavailable) → `.required` (safe default).
  nonisolated static func kind(for regionIdentifier: String?) -> ConsentJurisdiction {
    guard let code = regionIdentifier else {
      // Unknown region: default to strict consent.
      return .required
    }
    return strictOptInRegions.contains(code) ? .required : .autoOptin
  }

  // MARK: - Private: canonical region list (analytics-spec.md §7.2)

  /// All regions requiring explicit opt-in consent. To add or remove a region, update `docs/analytics-spec.md` §7.2 and this set together.
  /// Sources (as of 2026-05-03):
  /// - EU member states: GDPR + ePrivacy Directive
  /// - EEA (non-EU): IS, LI, NO — GDPR via EEA agreement
  /// - GB, GG, JE, IM — UK GDPR + PECR
  /// - CH — revFADP
  /// - KR — PIPA
  /// - CN — PIPL
  /// - BR — LGPD
  /// - TR — KVKK
  /// - TH — PDPA
  /// - CA — Law 25 (Quebec); applied CA-wide as a pragmatic choice
  nonisolated private static let strictOptInRegions: Set<String> = [
    // European Union (27 member states)
    "AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE",
    "FI", "FR", "DE", "GR", "HU", "IE", "IT", "LV",
    "LT", "LU", "MT", "NL", "PL", "PT", "RO", "SK",
    "SI", "ES", "SE",
    // EEA non-EU
    "IS", "LI", "NO",
    // United Kingdom and Crown Dependencies
    "GB", "GG", "JE", "IM",
    // Switzerland
    "CH",
    // South Korea
    "KR",
    // China (mainland)
    "CN",
    // Brazil
    "BR",
    // Turkey
    "TR",
    // Thailand
    "TH",
    // Canada (CA-wide coverage for Quebec Law 25)
    "CA",
  ]
}
