import Foundation
@testable import simple_recurring_budgets
import Testing

@Suite("EditableAmountConverter")
struct EditableAmountConverterTests {
  private let enUS = Locale(identifier: "en_US")
  private let deDE = Locale(identifier: "de_DE")

  // MARK: - Per-currency fraction digits (the core fix)

  @Test func fractionDigits_followCurrencyMinorUnits() {
    #expect(EditableAmountConverter.fractionDigits(for: "USD", locale: enUS) == 2)
    #expect(EditableAmountConverter.fractionDigits(for: "JPY", locale: enUS) == 0)
    #expect(EditableAmountConverter.fractionDigits(for: "BHD", locale: enUS) == 3)
  }

  // MARK: - Editable seeding (no grouping, currency-aware precision)

  @Test func usd_padsToTwoFractionDigitsWithoutGrouping() {
    let style = EditableAmountConverter(currencyCode: "USD", locale: enUS)
    #expect(style.editableText(1234.5) == "1234.50")
    #expect(style.editableText(1000) == "1000.00")
    #expect(style.editableText(4) == "4.00")
    #expect(style.editableText(Decimal(string: "5.5")) == "5.50")
  }

  /// A 3-decimal currency must NOT truncate an existing value to two places (the old `0...2` bug).
  @Test func bhd_preservesThreeFractionDigits() {
    let style = EditableAmountConverter(currencyCode: "BHD", locale: enUS)
    #expect(style.editableText(Decimal(string: "1.234")) == "1.234")
  }

  /// A 0-decimal currency shows no fraction digits.
  @Test func jpy_showsNoFractionDigits() {
    let style = EditableAmountConverter(currencyCode: "JPY", locale: enUS)
    #expect(style.editableText(1234) == "1234")
    #expect(!style.editableText(1234).contains("."))
  }

  @Test func nilSeedsToEmptyString() {
    let style = EditableAmountConverter(currencyCode: "USD", locale: enUS)
    #expect(style.editableText(nil).isEmpty)
  }

  @Test func editableText_usesLocaleDecimalSeparator() {
    let style = EditableAmountConverter(currencyCode: "EUR", locale: deDE)
    // de_DE uses "," for the decimal separator; seeding drops grouping separators and pads to 2 places.
    #expect(style.editableText(1234.5) == "1234,50")
  }

  // MARK: - Parsing

  @Test func parse_emptyOrWhitespace_isNil() throws {
    let strategy = EditableAmountParser(locale: enUS)
    #expect(try strategy.parse("") == nil)
    #expect(try strategy.parse("   ") == nil)
  }

  @Test func parse_threeDecimalValue_roundTrips() throws {
    let strategy = EditableAmountParser(locale: enUS)
    #expect(try strategy.parse("1.234") == Decimal(string: "1.234"))
  }

  @Test func parse_respectsLocaleDecimalSeparator() throws {
    let strategy = EditableAmountParser(locale: deDE)
    #expect(try strategy.parse("1,5") == Decimal(string: "1.5"))
  }

  /// Regression: the `.decimalPad` emits Arabic-Indic digits in ar_EG / ar_SA, and the old
  /// `Decimal(string:locale:)` returned nil for them, so the field rejected every keystroke.
  @Test func parse_acceptsArabicIndicDigits() throws {
    let strategy = EditableAmountParser(locale: Locale(identifier: "ar_EG"))
    #expect(try strategy.parse("١٢٣") == Decimal(123))
    #expect(try strategy.parse("١٢٣٫٥") == Decimal(string: "123.5"))
  }

  /// What the field actually does: seed a value, then parse the seeded string back.
  @Test func seedThenParse_roundTrips_arabicIndic() throws {
    let arEG = Locale(identifier: "ar_EG")
    let style = EditableAmountConverter(currencyCode: "EGP", locale: arEG)
    let seeded = style.editableText(Decimal(25))
    #expect(try style.parser.parse(seeded) == Decimal(25))
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
