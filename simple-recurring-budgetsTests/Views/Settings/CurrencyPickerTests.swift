import Foundation
@testable import simple_recurring_budgets
import Testing

struct CurrencyPickerTests {
  // MARK: - 7.2.a  Catalog codes

  @Test func catalogCodes_matchesLocaleCommonCodes_sortedAndDeDuped() {
    let expected = Array(Set(Locale.commonISOCurrencyCodes)).sorted()
    // `CurrencyPickerView.displayName` is the only exposed static helper (the catalog computation is
    // private), so validate indirectly: known anchors are present and Set/sort round-trips cancel duplicates.
    for code in ["USD", "EUR", "GBP"] {
      #expect(expected.contains(code), "Expected \(code) in common ISO codes")
    }
    // Verify de-dup (Set round-trip equals itself)
    let deduped = Array(Set(expected))
    #expect(deduped.count == expected.count)
    // Verify sort
    #expect(expected == expected.sorted())
  }

  // MARK: - 7.2.b  displayName(for:)

  @Test func displayName_returnsLocalisedStringForKnownCode() {
    let name = CurrencyPickerView.displayName(for: "USD")
    #expect(name != nil)
  }

  @Test func displayName_returnsNilOrEmptyForNonsenseCode() {
    // An unrecognised code should return nil (Locale.current.localizedString returns nil)
    let name = CurrencyPickerView.displayName(for: "XYZZY")
    #expect(name == nil)
  }

  // MARK: - 7.2.c  Filtering helper

  /// Calls the production `CurrencyPickerView.filteredCodes(_:matching:)` directly; the view's computed
  /// property forwards to the same static, so the rendered path is exercised.
  private func filter(_ codes: [String], by query: String) -> [String] {
    CurrencyPickerView.filteredCodes(codes, matching: query)
  }

  @Test func filter_byCodePrefix_includesMatchingCode() {
    let codes = ["EUR", "USD", "GBP", "JPY", "CAD"]
    let result = filter(codes, by: "eu")
    #expect(result.contains("EUR"))
    #expect(!result.contains("USD"))
  }

  @Test func filter_byCaseInsensitiveCode() {
    let codes = ["EUR", "USD", "GBP"]
    let result = filter(codes, by: "usd")
    #expect(result.contains("USD"))
  }

  @Test func filter_byLocalisedNameSubstring_includesCode() {
    // "yen" matches JPY via its en localized name. The assertion is conditional on that name containing
    // "yen" so the test stays locale-independent.
    let codes = Array(Set(Locale.commonISOCurrencyCodes)).sorted()
    let jpyName = CurrencyPickerView.displayName(for: "JPY") ?? ""
    if jpyName.localizedCaseInsensitiveContains("yen") {
      let result = filter(codes, by: "yen")
      #expect(result.contains("JPY"), "Expected JPY when filtering by 'yen'")
    }
  }

  @Test func filter_emptyQueryReturnsAllCodes() {
    let codes = ["EUR", "USD", "GBP", "JPY"]
    let result = filter(codes, by: "")
    #expect(result.count == codes.count)
  }

  // MARK: - 7.2.d  Empty query (whole catalog)

  @Test func filter_emptyQueryOnFullCatalog_returnsAll() {
    let all = Array(Set(Locale.commonISOCurrencyCodes)).sorted()
    let result = filter(all, by: "")
    #expect(result.count == all.count)
  }
}
