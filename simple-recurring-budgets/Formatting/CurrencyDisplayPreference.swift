import Foundation

/// How monetary amounts are displayed app-wide. Stored in `AppSettings` via `NSUbiquitousKeyValueStore`
/// (key `"currencyDisplay"`). Consumed by `Decimal.formatted(currencyCode:display:locale:)`, the single
/// blessed formatter for monetary rendering.
enum CurrencyDisplayPreference: String, CaseIterable, Identifiable, Codable {
  /// Show only the locale's conventional currency symbol, e.g. "$25.00" or "25,00 €".
  case symbol
  /// Show only the ISO 4217 code, e.g. "USD 25.00".
  case code
  /// Show the ISO code prepended to the symbol form, e.g. "USD $25.00".
  case codeAndSymbol

  var id: Self {
    self
  }

  // MARK: - Localized label

  var label: String {
    switch self {
    case .symbol:
      String(
        localized: "settings.currencyDisplay.symbol",
        defaultValue: "Symbol",
        comment: "Currency display option: show only the symbol, e.g. $25"
      )
    case .code:
      String(
        localized: "settings.currencyDisplay.code",
        defaultValue: "Code",
        comment: "Currency display option: show only the ISO code, e.g. USD 25"
      )
    case .codeAndSymbol:
      String(
        localized: "settings.currencyDisplay.codeAndSymbol",
        defaultValue: "Code + Symbol",
        comment: "Currency display option: show both code and symbol, e.g. USD $25"
      )
    }
  }

  // MARK: - Formatted example

  /// Locale-aware preview of how `Decimal(25)` renders under this preference. The currency code comes from
  /// `locale.currency?.identifier`, falling back to `"USD"`. The default `Locale.autoupdatingCurrent` shows the
  /// user's own currency in the Settings picker; tests pass an explicit locale.
  func example(locale: Locale = .autoupdatingCurrent) -> String {
    let code = locale.currency?.identifier ?? "USD"
    return Decimal(25).formatted(currencyCode: code, display: self, locale: locale)
  }

  // MARK: - Affixes

  /// Currency symbol/code text to place around an editable amount field, as a `leading` part (before the
  /// digits) and a `trailing` part (after), not a full amount string.
  ///
  /// The keypad-driven field can't bake the symbol into its editable text, so the view renders these as
  /// adjacent decoration. Each side is **derived from the same currency `FormatStyle` the display path uses**
  /// (`Decimal.formatted(currencyCode:display:locale:)`) so the editor agrees with the rest of the app:
  /// "$25" gives `leading = "$"`, "25,00 €" gives `trailing = " €"`, including locale spacing.
  func affixes(for currencyCode: String, locale: Locale = .autoupdatingCurrent) -> (leading: String, trailing: String) {
    switch self {
    case .symbol:
      return Self.splitAffixes(.currency(code: currencyCode).locale(locale))
    case .code:
      return Self.splitAffixes(.currency(code: currencyCode).presentation(.isoCode).locale(locale))
    case .codeAndSymbol:
      // No native presentation matches the app's "USD $25" concat: keep the ISO code leading and append the
      // symbol form's output.
      let (leading, trailing) = Self.splitAffixes(.currency(code: currencyCode).locale(locale))
      return (leading: "\(currencyCode) \(leading)", trailing: trailing)
    }
  }

  /// Splits a currency `FormatStyle` into the text before/after the numeric core by formatting a sentinel
  /// amount as an `AttributedString` and partitioning runs on the number-part / number-symbol attributes,
  /// keeping symbol position and locale spacing aligned with the display formatter.
  private static func splitAffixes(_ style: Decimal.FormatStyle.Currency) -> (leading: String, trailing: String) {
    let attributed = Decimal(0).formatted(style.attributed)
    let runs = Array(attributed.runs)

    func isNumericCore(_ run: AttributedString.Runs.Run) -> Bool {
      if run.numberPart != nil {
        return true
      }
      switch run.numberSymbol {
      case .decimalSeparator, .groupingSeparator, .sign: return true
      default: return false
      }
    }

    guard let first = runs.firstIndex(where: isNumericCore),
          let last = runs.lastIndex(where: isNumericCore)
    else {
      return ("", "")
    }
    func text(_ slice: ArraySlice<AttributedString.Runs.Run>) -> String {
      slice.map { String(attributed[$0.range].characters) }.joined()
    }
    return (leading: text(runs[..<first]), trailing: text(runs[(last + 1)...]))
  }
}
