import Foundation

/// Converts between `Decimal?` and the editable text of the Amount/Allocation fields.
///
/// The fields are backed by `UITextField` (see `DecimalInputField`), not SwiftUI's `TextField`, because
/// `TextField(value:format:)` rejects keystrokes whenever parsing throws (which broke entry in RTL /
/// non-Western-digit locales) and `TextField(text:)` + `.onChange` into an `@Observable` model fails to
/// render typed text until focus resigns. Callers seed the field via `editableText(_:)` and convert edits
/// back with `parseStrategy`. (If those SwiftUI bugs are fixed, this type can back a native `TextField`
/// directly again — see issue #122.)
///
/// It is **currency-aware**: `editableText(_:)` seeds an existing value at the currency's minor-unit
/// precision (e.g. 3 digits for BHD, 0 for JPY); `parse` is locale-aware and accepts whatever numbering
/// system the locale's keyboard emits (Western, Arabic-Indic, Devanagari, …).
struct OptionalDecimalFormatStyle: ParseableFormatStyle {
  typealias FormatInput = Decimal?
  typealias FormatOutput = String

  /// ISO 4217 code whose minor-unit count drives the maximum fraction length.
  var currencyCode: String
  /// Locale for grouping/decimal separators and digit parsing. Defaults to the user's locale.
  var locale: Locale = .autoupdatingCurrent

  func format(_ value: Decimal?) -> String {
    guard let value else { return "" }
    let maxFraction = Self.fractionDigits(for: currencyCode, locale: locale)
    return value.formatted(
      .number.precision(.fractionLength(0 ... maxFraction)).locale(locale)
    )
  }

  /// Locale-aware string for *seeding* the editable field: no grouping separators (so mid-number editing is
  /// clean) and fraction digits up to the currency's minor-unit count (so an existing 3-decimal value is not
  /// truncated). Empty string for `nil`.
  func editableText(_ value: Decimal?) -> String {
    guard let value else { return "" }
    let maxFraction = Self.fractionDigits(for: currencyCode, locale: locale)
    return value.formatted(
      .number.grouping(.never).precision(.fractionLength(0 ... maxFraction)).locale(locale)
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

  /// Locale used to interpret grouping/decimal separators and digit scripts. Mirrors the format style.
  var locale: Locale = .autoupdatingCurrent

  func parse(_ value: String) throws -> Decimal? {
    let trimmed = value.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return nil }
    // Parse through a locale-aware `.number` style rather than `Decimal(string:locale:)`. The latter returns
    // nil for non-Western digits; the FormatStyle parser accepts whatever numbering system the locale uses
    // (Western, Arabic-Indic, Devanagari, …) plus locale grouping/decimal separators.
    return try Decimal(trimmed, format: Decimal.FormatStyle(locale: locale))
  }
}
