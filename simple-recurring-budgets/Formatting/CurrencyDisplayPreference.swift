import Foundation

/// How monetary amounts are displayed app-wide.
///
/// Stored in `AppSettings` via `NSUbiquitousKeyValueStore` (key `"currencyDisplay"`).
/// Consumed by `Decimal.formatted(currencyCode:display:locale:)` — the single
/// blessed formatter for all monetary rendering in the app.
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

  /// Returns a locale-aware preview of how `Decimal(25)` renders under this
  /// preference for the supplied locale's currency.
  ///
  /// The currency code is resolved from `locale.currency?.identifier`, falling
  /// back to `"USD"` when none is available (mirrors F-3.04 convention).
  /// The default `Locale.autoupdatingCurrent` lets production callers (the
  /// Settings picker) show the user's own currency; pass an explicit locale
  /// in tests for deterministic results.
  func example(locale: Locale = .autoupdatingCurrent) -> String {
    let code = locale.currency?.identifier ?? "USD"
    return Decimal(25).formatted(currencyCode: code, display: self, locale: locale)
  }

  // MARK: - Affixes

  /// Currency symbol / code text to place around an editable amount field, split into a `leading` part
  /// (before the digits) and a `trailing` part (after the digits) — not a full amount string.
  ///
  /// The keypad-driven amount field can't bake the symbol into its editable text, so the view renders these
  /// as adjacent decoration. Crucially, the side each part lands on is **derived from the same currency
  /// `FormatStyle` the display path uses** (`Decimal.formatted(currencyCode:display:locale:)`), so the editor
  /// agrees with the rest of the app: leading-symbol locales (e.g. "$25") get `leading = "$"`, trailing-symbol
  /// locales (e.g. "25,00 €") get `trailing = " €"`, including any locale spacing.
  func affixes(for currencyCode: String, locale: Locale = .autoupdatingCurrent) -> (leading: String, trailing: String) {
    switch self {
    case .symbol:
      return Self.splitAffixes(.currency(code: currencyCode).locale(locale))
    case .code:
      return Self.splitAffixes(.currency(code: currencyCode).presentation(.isoCode).locale(locale))
    case .codeAndSymbol:
      // No native presentation matches the app's "USD $25" concat, so keep the ISO code leading and append
      // it to whatever the symbol form produces.
      let (leading, trailing) = Self.splitAffixes(.currency(code: currencyCode).locale(locale))
      return (leading: "\(currencyCode) \(leading)", trailing: trailing)
    }
  }

  /// Splits a currency `FormatStyle` into the text before and after the numeric core by formatting a sentinel
  /// amount as an `AttributedString` and partitioning its runs on the number-part / number-symbol attributes.
  /// This keeps symbol position and locale spacing exactly aligned with the display formatter.
  private static func splitAffixes(_ style: Decimal.FormatStyle.Currency) -> (leading: String, trailing: String) {
    let attributed = Decimal(0).formatted(style.attributed)
    let runs = Array(attributed.runs)

    func isNumericCore(_ run: AttributedString.Runs.Run) -> Bool {
      if run.numberPart != nil { return true }
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
