@testable import simple_recurring_budgets
import Testing

/// §18.1 test contract #1 — ConsentJurisdiction resolution.
@Suite("ConsentJurisdiction — §18.1 #1")
struct ConsentJurisdictionTests {
  // MARK: - Required jurisdictions (should all resolve to .required)

  @Test("EU member states resolve to required", arguments: [
    "AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE",
    "FI", "FR", "DE", "GR", "HU", "IE", "IT", "LV",
    "LT", "LU", "MT", "NL", "PL", "PT", "RO", "SK",
    "SI", "ES", "SE",
  ])
  func euMemberStatesRequired(region: String) {
    #expect(ConsentJurisdiction.kind(for: region) == .required)
  }

  @Test("EEA non-EU states resolve to required", arguments: ["IS", "LI", "NO"])
  func eeaNonEuRequired(region: String) {
    #expect(ConsentJurisdiction.kind(for: region) == .required)
  }

  @Test("UK and Crown Dependencies resolve to required", arguments: ["GB", "GG", "JE", "IM"])
  func ukAndCrownDependenciesRequired(region: String) {
    #expect(ConsentJurisdiction.kind(for: region) == .required)
  }

  @Test("Additional strict-opt-in countries resolve to required", arguments: [
    "CH", "KR", "CN", "BR", "TR", "TH", "CA",
  ])
  func additionalStrictRequired(region: String) {
    #expect(ConsentJurisdiction.kind(for: region) == .required)
  }

  @Test("nil region resolves to required (conservative default)")
  func nilRegionIsRequired() {
    #expect(ConsentJurisdiction.kind(for: nil) == .required)
  }

  // MARK: - Auto opt-in jurisdictions

  @Test("auto opt-in jurisdictions resolve to autoOptin", arguments: [
    "US", "JP", "AU", "IN", "MX", "NZ", "ZA", "SG", "HK",
  ])
  func autoOptInJurisdictions(region: String) {
    #expect(ConsentJurisdiction.kind(for: region) == .autoOptin)
  }
}
