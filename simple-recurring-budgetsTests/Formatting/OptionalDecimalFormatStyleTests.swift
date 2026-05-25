import Foundation
@testable import simple_recurring_budgets
import Testing

@Suite("OptionalDecimalFormatStyle")
struct OptionalDecimalFormatStyleTests {
  private let enUS = Locale(identifier: "en_US")
  private let deDE = Locale(identifier: "de_DE")

  // MARK: - Per-currency fraction digits (the core fix)

  @Test func fractionDigits_followCurrencyMinorUnits() {
    #expect(OptionalDecimalFormatStyle.fractionDigits(for: "USD", locale: enUS) == 2)
    #expect(OptionalDecimalFormatStyle.fractionDigits(for: "JPY", locale: enUS) == 0)
    #expect(OptionalDecimalFormatStyle.fractionDigits(for: "BHD", locale: enUS) == 3)
  }

  // MARK: - Formatting

  @Test func usd_keepsUpToTwoFractionDigits() {
    let style = OptionalDecimalFormatStyle(currencyCode: "USD", locale: enUS)
    #expect(style.format(1234.5) == "1,234.5")
    #expect(style.format(1000) == "1,000")
  }

  /// A 3-decimal currency must NOT truncate an existing value to two places (the old `0...2` bug).
  @Test func bhd_preservesThreeFractionDigits() {
    let style = OptionalDecimalFormatStyle(currencyCode: "BHD", locale: enUS)
    #expect(style.format(Decimal(string: "1.234")) == "1.234")
  }

  /// A 0-decimal currency shows no fraction digits.
  @Test func jpy_showsNoFractionDigits() {
    let style = OptionalDecimalFormatStyle(currencyCode: "JPY", locale: enUS)
    #expect(style.format(1234) == "1,234")
    #expect(!style.format(1234).contains("."))
  }

  @Test func nilFormatsToEmptyString() {
    let style = OptionalDecimalFormatStyle(currencyCode: "USD", locale: enUS)
    #expect(style.format(nil).isEmpty)
  }

  @Test func format_usesLocaleSeparators() {
    let style = OptionalDecimalFormatStyle(currencyCode: "EUR", locale: deDE)
    // de_DE uses "." for grouping and "," for the decimal separator.
    #expect(style.format(1234.5) == "1.234,5")
  }

  // MARK: - Parsing

  @Test func parse_emptyOrWhitespace_isNil() throws {
    let strategy = OptionalDecimalParseStrategy(locale: enUS)
    #expect(try strategy.parse("") == nil)
    #expect(try strategy.parse("   ") == nil)
  }

  @Test func parse_threeDecimalValue_roundTrips() throws {
    let strategy = OptionalDecimalParseStrategy(locale: enUS)
    #expect(try strategy.parse("1.234") == Decimal(string: "1.234"))
  }

  @Test func parse_respectsLocaleDecimalSeparator() throws {
    let strategy = OptionalDecimalParseStrategy(locale: deDE)
    #expect(try strategy.parse("1,5") == Decimal(string: "1.5"))
  }

  /// Regression: the `.decimalPad` emits Arabic-Indic digits in ar_EG / ar_SA, and the old
  /// `Decimal(string:locale:)` returned nil for them, so the field rejected every keystroke.
  @Test func parse_acceptsArabicIndicDigits() throws {
    let strategy = OptionalDecimalParseStrategy(locale: Locale(identifier: "ar_EG"))
    #expect(try strategy.parse("١٢٣") == Decimal(123))
    #expect(try strategy.parse("١٢٣٫٥") == Decimal(string: "123.5"))
  }

  /// What the field actually does: render a value, then parse the rendered string back.
  @Test func formatThenParse_roundTrips_arabicIndic() throws {
    let arEG = Locale(identifier: "ar_EG")
    let style = OptionalDecimalFormatStyle(currencyCode: "EGP", locale: arEG)
    let rendered = style.format(Decimal(25))
    #expect(try style.parseStrategy.parse(rendered) == Decimal(25))
  }
}

@Suite("CurrencyDisplayPreference.affixes")
struct CurrencyDisplayAffixesTests {
  private let enUS = Locale(identifier: "en_US")
  private let frFR = Locale(identifier: "fr_FR")
  private let jaJP = Locale(identifier: "ja_JP")

  /// Leading-symbol locale: symbol on the leading side, nothing trailing.
  @Test func symbol_usd_enUS_isLeading() {
    let (leading, trailing) = CurrencyDisplayPreference.symbol.affixes(for: "USD", locale: enUS)
    #expect(leading.contains("$"))
    #expect(trailing.isEmpty)
  }

  /// Trailing-symbol locale: nothing leading, symbol on the trailing side.
  @Test func symbol_eur_frFR_isTrailing() {
    let (leading, trailing) = CurrencyDisplayPreference.symbol.affixes(for: "EUR", locale: frFR)
    #expect(leading.isEmpty)
    #expect(trailing.contains("€"))
  }

  /// The affix side must agree with the display formatter (the whole point of the fix): the rendered amount
  /// should begin with the leading affix and end with the trailing affix.
  @Test func affixes_matchDisplayFormatter() {
    for (code, locale) in [("USD", enUS), ("EUR", frFR), ("JPY", jaJP)] {
      let (leading, trailing) = CurrencyDisplayPreference.symbol.affixes(for: code, locale: locale)
      let display = Decimal(25).formatted(currencyCode: code, display: .symbol, locale: locale)
      #expect(display.hasPrefix(leading))
      #expect(display.hasSuffix(trailing))
    }
  }

  @Test func code_enUS_isLeading() {
    let (leading, trailing) = CurrencyDisplayPreference.code.affixes(for: "USD", locale: enUS)
    #expect(leading.contains("USD"))
    #expect(trailing.isEmpty)
  }

  @Test func codeAndSymbol_prependsCode() {
    let (leading, _) = CurrencyDisplayPreference.codeAndSymbol.affixes(for: "USD", locale: enUS)
    #expect(leading.contains("USD"))
    #expect(leading.contains("$"))
  }
}
