import Foundation

/// Converts between `Decimal?` and the editable text of the Amount/Allocation fields.
///
/// The fields are backed by `UITextField` (see `DecimalInputField`), not SwiftUI's `TextField`:
/// `TextField(value:format:)` rejects keystrokes whenever parsing throws (broke entry in RTL /
/// non-Western-digit locales), and `TextField(text:)` + `.onChange` into an `@Observable` model doesn't
/// render typed text until focus resigns. Callers seed via `editableText(_:)` and convert edits back with
/// `parser`. If those SwiftUI bugs are fixed, this type can back a native `TextField` again.
///
/// **Currency-aware:** `editableText(_:)` uses the currency's minor-unit precision (3 digits for BHD, 0 for
/// JPY); `parser` is locale-aware and accepts whatever numbering system the keyboard emits (Western,
/// Arabic-Indic, Devanagari, …).
///
/// Deliberately *not* a `ParseableFormatStyle`: the UIKit field calls `editableText` and `parser.parse`
/// directly, so the `format(_:)`/protocol machinery that only serves `TextField(value:format:)` would be
/// dead weight. Reinstating the conformance is mechanical if a native field returns.
struct EditableAmountConverter {
  /// ISO 4217 code whose minor-unit count drives the maximum fraction length.
  var currencyCode: String
  /// Locale for grouping/decimal separators and digit parsing. Defaults to the user's locale.
  var locale: Locale = .autoupdatingCurrent

  /// Locale-aware string for *seeding* the editable field: no grouping separators (so mid-number editing is
  /// clean) and fraction digits up to the currency's minor-unit count (so an existing 3-decimal value is not
  /// truncated). Empty string for `nil`.
  func editableText(_ value: Decimal?) -> String {
    guard let value else { return "" }
    let maxFraction = Self.fractionDigits(for: currencyCode, locale: locale)
    return value.formatted(
      .number.grouping(.never).precision(.fractionLength(maxFraction ... maxFraction)).locale(locale)
    )
  }

  var parser: EditableAmountParser {
    EditableAmountParser(locale: locale)
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

/// Parses the editable text of an amount field back into `Decimal?`, paired with ``EditableAmountConverter``.
struct EditableAmountParser {
  /// Locale used to interpret grouping/decimal separators and digit scripts. Mirrors the converter.
  var locale: Locale = .autoupdatingCurrent

  func parse(_ value: String) throws -> Decimal? {
    let trimmed = value.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return nil }
    // Parse through a locale-aware `.number` style, not `Decimal(string:locale:)`, which returns nil for
    // non-Western digits; the FormatStyle parser accepts the locale's numbering system plus its
    // grouping/decimal separators.
    return try Decimal(trimmed, format: Decimal.FormatStyle(locale: locale))
  }
}
