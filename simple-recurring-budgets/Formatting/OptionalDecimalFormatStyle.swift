import Foundation

/// Used by `AddEditExpenseView`'s Amount field to allow blank input to map to `Decimal?` rather than `0`.
///
/// The same `ParseableFormatStyle` is reused by `AddEditBudgetView`'s Allocation field. Maps between
/// `Decimal?` and a plain numeric string: empty or whitespace-only input parses to `nil`; otherwise parses
/// with the supplied `locale`.
///
/// The field is keypad-driven, so the currency symbol is rendered as adjacent decoration by the view (see
/// `CurrencyDisplayPreference.affixes(for:locale:)`) rather than baked into the editable text. This style is
/// therefore a *plain number* style, but it is made **currency-aware** in one respect: the maximum fraction
/// length follows the currency's standard minor-unit count (JPY → 0, USD → 2, BHD → 3). The minimum stays at
/// 0 so partial/blank input keeps working while typing.
struct OptionalDecimalFormatStyle: ParseableFormatStyle {
  typealias FormatInput = Decimal?
  typealias FormatOutput = String

  /// ISO 4217 code whose minor-unit count drives the maximum fraction length.
  var currencyCode: String
  /// Locale for grouping/decimal separators. Defaults to the user's locale; pass explicitly in tests.
  var locale: Locale = .autoupdatingCurrent

  func format(_ value: Decimal?) -> String {
    guard let value else { return "" }
    let maxFraction = Self.fractionDigits(for: currencyCode, locale: locale)
    return value.formatted(
      .number.precision(.fractionLength(0 ... maxFraction)).locale(locale)
    )
  }

  var parseStrategy: OptionalDecimalParseStrategy {
    OptionalDecimalParseStrategy(locale: locale)
  }

  /// Standard number of fraction digits for `currencyCode` (its minor-unit count). Falls back to the
  /// formatter's default (2) when the currency is unknown.
  static func fractionDigits(for currencyCode: String, locale: Locale) -> Int {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = currencyCode
    formatter.locale = locale
    return formatter.maximumFractionDigits
  }
}

/// Parse strategy paired with ``OptionalDecimalFormatStyle``.
struct OptionalDecimalParseStrategy: ParseStrategy {
  typealias ParseInput = String
  typealias ParseOutput = Decimal?

  /// Locale used to interpret grouping/decimal separators. Mirrors the format style's locale.
  var locale: Locale = .autoupdatingCurrent

  func parse(_ value: String) throws -> Decimal? {
    let trimmed = value.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return nil }
    // Parse through a locale-aware `.number` style rather than `Decimal(string:locale:)`. The latter returns
    // nil for non-Western digits — e.g. the Arabic-Indic numerals (٠١٢٣…) the `.decimalPad` emits in
    // ar_EG / ar_SA — which made the field reject every keystroke in those locales. The FormatStyle parser
    // accepts the same digits its formatter produces, plus Western input and locale grouping separators.
    return try Decimal(trimmed, format: Decimal.FormatStyle(locale: locale))
  }
}
