import Foundation
@testable import simple_recurring_budgets
import Testing

// MARK: - Shared fixtures

private let enUS = Locale(identifier: "en_US")
private let deDE = Locale(identifier: "de_DE")

private let utcGregorian: Calendar = {
  var c = Calendar(identifier: .gregorian)
  c.timeZone = TimeZone(identifier: "UTC")!
  c.locale = enUS
  return c
}()

private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
  var comps = DateComponents()
  comps.year = year; comps.month = month; comps.day = day
  comps.hour = hour; comps.minute = 0; comps.second = 0
  comps.timeZone = TimeZone(identifier: "UTC")
  return Calendar(identifier: .gregorian).date(from: comps)!
}

// MARK: - Decimal.formatted(currencyCode:)

struct DecimalCurrencyFormattingTests {
  @Test func usd_enUS_basic() {
    let value: Decimal = 1234.5
    #expect(value.formatted(currencyCode: "USD", locale: enUS) == "$1,234.50")
  }

  @Test func usd_enUS_zero_shows_two_fraction_digits() {
    let value: Decimal = 0
    #expect(value.formatted(currencyCode: "USD", locale: enUS) == "$0.00")
  }

  @Test func eur_deDE_contains_euro_symbol() {
    let value: Decimal = 1234.5
    let result = (value as Decimal).formatted(currencyCode: "EUR", locale: deDE)
    #expect(result.contains("€"))
    #expect(!result.contains("$"))
  }

  @Test func negative_usd_enUS_renders_with_sign() {
    let value: Decimal = -42
    // Foundation renders negative USD with a leading "-$" in en_US.
    let result = value.formatted(currencyCode: "USD", locale: enUS)
    #expect(result.contains("42"))
    #expect(result.contains("$"))
    #expect(result.first == "-" || result.contains("(42"))
  }
}

// MARK: - Decimal.formatted(currencyCode:display:locale:)

struct DecimalDisplayFormattingTests {
  @Test func symbol_matchesDefaultBehavior_enUS() {
    let value: Decimal = 25
    let symbol = value.formatted(currencyCode: "USD", display: .symbol, locale: enUS)
    let baseline = value.formatted(currencyCode: "USD", locale: enUS)
    #expect(symbol == baseline)
  }

  @Test func code_usesISOCode_enUS() {
    let value: Decimal = 25
    let result = value.formatted(currencyCode: "USD", display: .code, locale: enUS)
    #expect(result.contains("USD"))
    #expect(!result.contains("$"))
  }

  @Test func codeAndSymbol_containsCodeAndSymbol_enUS() {
    let value: Decimal = 25
    let result = value.formatted(currencyCode: "USD", display: .codeAndSymbol, locale: enUS)
    #expect(result.contains("USD"))
    #expect(result.contains("$"))
    let components = result.components(separatedBy: " ")
    #expect(components.first == "USD", "ISO code should be the first space-delimited token")
  }

  @Test func symbol_eur_deDE_containsEuroSign() {
    let value: Decimal = 25
    let result = value.formatted(currencyCode: "EUR", display: .symbol, locale: deDE)
    #expect(result.contains("€"))
  }

  @Test func code_eur_deDE_containsEURNotEuroSign() {
    let value: Decimal = 25
    let result = value.formatted(currencyCode: "EUR", display: .code, locale: deDE)
    #expect(result.contains("EUR"))
    #expect(!result.contains("€"))
  }

  @Test func codeAndSymbol_eur_deDE_containsBothCodeAndSymbol() {
    let value: Decimal = 25
    let result = value.formatted(currencyCode: "EUR", display: .codeAndSymbol, locale: deDE)
    #expect(result.contains("EUR"))
    #expect(result.contains("€"))
  }

  @Test func code_jpy_jaJP_containsJPY() {
    let value: Decimal = 2500
    let locale = Locale(identifier: "ja_JP")
    let result = value.formatted(currencyCode: "JPY", display: .code, locale: locale)
    #expect(result.contains("JPY"))
  }

  @Test func code_sar_arSA_containsSAR() {
    let value: Decimal = 25
    let locale = Locale(identifier: "ar_SA")
    let result = value.formatted(currencyCode: "SAR", display: .code, locale: locale)
    #expect(result.contains("SAR"))
  }

  @Test func defaultDisplayParameter_behavesLikeSymbol() {
    let value: Decimal = 25
    // The defaulted `display:` should produce the same result as `.symbol` explicitly.
    let withDefault = value.formatted(currencyCode: "USD", locale: enUS)
    let withSymbol = value.formatted(currencyCode: "USD", display: .symbol, locale: enUS)
    #expect(withDefault == withSymbol)
  }
}

// MARK: - CarryOverFormatter

struct CarryOverFormatterTests {
  @Test func surplus_returns_magnitude_and_surplus_sign() {
    let display = CarryOverFormatter.display(
      Decimal(3),
      currencyCode: "USD",
      locale: enUS
    )
    #expect(display.sign == .surplus)
    #expect(display.amount == "$3.00")
    #expect(display.label != nil)
    #expect(display.label?.isEmpty == false)
  }

  @Test func deficit_returns_magnitude_not_negative_string() {
    let display = CarryOverFormatter.display(
      Decimal(-5),
      currencyCode: "USD",
      locale: enUS
    )
    #expect(display.sign == .deficit)
    #expect(display.amount == "$5.00")
    #expect(!display.amount.contains("-"))
    #expect(display.label != nil)
  }

  @Test func zero_returns_zero_sign_and_nil_label() {
    let display = CarryOverFormatter.display(
      Decimal(0),
      currencyCode: "USD",
      locale: enUS
    )
    #expect(display.sign == .zero)
    #expect(display.amount == "$0.00")
    #expect(display.label == nil)
  }

  @Test func uses_provided_currency_code() {
    let display = CarryOverFormatter.display(
      Decimal(7),
      currencyCode: "EUR",
      locale: deDE
    )
    #expect(display.amount.contains("€"))
    #expect(display.amount.contains("7"))
  }

  // MARK: - display parameter threading

  @Test func displayCode_doesNotContainSymbol() {
    let result = CarryOverFormatter.display(
      Decimal(10),
      currencyCode: "USD",
      display: .code,
      locale: enUS
    )
    #expect(result.amount.contains("USD"))
    #expect(!result.amount.contains("$"))
    #expect(result.sign == .surplus)
  }

  @Test func displayCodeAndSymbol_containsBothCodeAndSymbol() {
    let result = CarryOverFormatter.display(
      Decimal(10),
      currencyCode: "USD",
      display: .codeAndSymbol,
      locale: enUS
    )
    #expect(result.amount.contains("USD"))
    #expect(result.amount.contains("$"))
    #expect(result.sign == .surplus)
  }

  @Test func displayCode_deficit_signAndMagnitudeUnchanged() {
    let result = CarryOverFormatter.display(
      Decimal(-10),
      currencyCode: "USD",
      display: .code,
      locale: enUS
    )
    #expect(result.sign == .deficit)
    #expect(!result.amount.contains("-"), "magnitude should not be negative")
    #expect(result.amount.contains("USD"))
  }

  @Test func defaultDisplay_equalsSymbol() {
    let withDefault = CarryOverFormatter.display(Decimal(5), currencyCode: "USD", locale: enUS)
    let withSymbol = CarryOverFormatter.display(Decimal(5), currencyCode: "USD", display: .symbol, locale: enUS)
    #expect(withDefault.amount == withSymbol.amount)
    #expect(withDefault.sign == withSymbol.sign)
  }
}

// MARK: - Date.formattedForExpenseList

struct DateExpenseListFormattingTests {
  @Test func today_starts_with_today_label() {
    let reference = date(2026, 4, 17, hour: 15)
    let sameDay = date(2026, 4, 17, hour: 9)
    let result = sameDay.formattedForExpenseList(
      relativeTo: reference,
      calendar: utcGregorian,
      locale: enUS
    )
    #expect(result.lowercased().contains("today"))
  }

  @Test func yesterday_starts_with_yesterday_label() {
    let reference = date(2026, 4, 17, hour: 10)
    let prior = date(2026, 4, 16, hour: 20)
    let result = prior.formattedForExpenseList(
      relativeTo: reference,
      calendar: utcGregorian,
      locale: enUS
    )
    #expect(result.lowercased().contains("yesterday"))
  }

  @Test func older_date_uses_full_date_and_time() {
    let reference = date(2026, 4, 17, hour: 10)
    let older = date(2025, 11, 3, hour: 14)
    let result = older.formattedForExpenseList(
      relativeTo: reference,
      calendar: utcGregorian,
      locale: enUS
    )
    #expect(!result.lowercased().contains("today"))
    #expect(!result.lowercased().contains("yesterday"))
    #expect(result.contains("2025"))
    // Should include both date and time components.
    #expect(result.contains("11") || result.contains("Nov"))
  }
}
