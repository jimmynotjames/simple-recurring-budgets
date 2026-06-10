import Foundation
@testable import simple_recurring_budgets
import Testing

@Suite("CurrencyDisplayPreference")
struct CurrencyDisplayPreferenceTests {
  // MARK: - Raw values

  @Test func rawValues_areCorrect() {
    #expect(CurrencyDisplayPreference.symbol.rawValue == "symbol")
    #expect(CurrencyDisplayPreference.code.rawValue == "code")
    #expect(CurrencyDisplayPreference.codeAndSymbol.rawValue == "codeAndSymbol")
  }

  // MARK: - CaseIterable order

  @Test func allCases_orderedAsSpecified() {
    #expect(CurrencyDisplayPreference.allCases == [.symbol, .code, .codeAndSymbol])
  }

  // MARK: - Identifiable

  @Test func identifiable_idEqualsCase() {
    for pref in CurrencyDisplayPreference.allCases {
      #expect(pref.id == pref)
    }
  }

  // MARK: - Codable round-trip

  @Test func codable_roundTrip() throws {
    for pref in CurrencyDisplayPreference.allCases {
      let encoded = try JSONEncoder().encode(pref)
      let decoded = try JSONDecoder().decode(CurrencyDisplayPreference.self, from: encoded)
      #expect(decoded == pref)
    }
  }

  // MARK: - Localized label

  /// Exact wording is owned by the String Catalog (and varies by run locale),
  /// so assert the structural contract: every case resolves to a non-empty
  /// label and no two cases collapse to the same string.
  @Test func label_nonEmptyAndDistinct_forAllCases() {
    let labels = CurrencyDisplayPreference.allCases.map(\.label)
    for label in labels {
      #expect(!label.isEmpty)
    }
    #expect(Set(labels).count == CurrencyDisplayPreference.allCases.count)
  }

  // MARK: - example(locale:) correctness

  private let enUS = Locale(identifier: "en_US")
  private let frFR = Locale(identifier: "fr_FR")
  private let jaJP = Locale(identifier: "ja_JP")
  private let arSA = Locale(identifier: "ar_SA")

  /// The example output must equal the canonical formatter for each case and locale.
  @Test func example_matchesCanonicalFormatter_enUS() {
    let locale = Locale(identifier: "en_US")
    let code = locale.currency?.identifier ?? "USD"
    for pref in CurrencyDisplayPreference.allCases {
      let expected = Decimal(25).formatted(currencyCode: code, display: pref, locale: locale)
      #expect(pref.example(locale: locale) == expected)
    }
  }

  @Test func example_matchesCanonicalFormatter_frFR() {
    let locale = Locale(identifier: "fr_FR")
    let code = locale.currency?.identifier ?? "USD"
    for pref in CurrencyDisplayPreference.allCases {
      let expected = Decimal(25).formatted(currencyCode: code, display: pref, locale: locale)
      #expect(pref.example(locale: locale) == expected)
    }
  }

  @Test func example_matchesCanonicalFormatter_jaJP() {
    let locale = Locale(identifier: "ja_JP")
    let code = locale.currency?.identifier ?? "USD"
    for pref in CurrencyDisplayPreference.allCases {
      let expected = Decimal(25).formatted(currencyCode: code, display: pref, locale: locale)
      #expect(pref.example(locale: locale) == expected)
    }
  }

  @Test func example_matchesCanonicalFormatter_arSA() {
    let locale = Locale(identifier: "ar_SA")
    let code = locale.currency?.identifier ?? "USD"
    for pref in CurrencyDisplayPreference.allCases {
      let expected = Decimal(25).formatted(currencyCode: code, display: pref, locale: locale)
      #expect(pref.example(locale: locale) == expected)
    }
  }

  /// When `locale.currency?.identifier` is nil, falls back to "USD".
  @Test func example_fallsBackToUSD_forNilCurrencyLocale() {
    // `Locale.init(identifier: "")` has no currency
    let noLocale = Locale(identifier: "")
    let usdCode = "USD"
    for pref in CurrencyDisplayPreference.allCases {
      let fromPref = pref.example(locale: noLocale)
      let expected = Decimal(25).formatted(currencyCode: usdCode, display: pref, locale: noLocale)
      #expect(fromPref == expected)
    }
  }

  /// Non-USD locales must NOT produce the en_US hard-coded strings.
  @Test func example_isNotEnUSLiterals_forNonUSDLocale() {
    let enUSLiterals: [CurrencyDisplayPreference: String] = [
      .symbol: "$25.00",
      .code: "USD 25.00",
      .codeAndSymbol: "USD $25.00",
    ]
    let frFR = Locale(identifier: "fr_FR")
    for pref in CurrencyDisplayPreference.allCases {
      #expect(pref.example(locale: frFR) != enUSLiterals[pref])
    }
  }
}
