//
//  CurrencyDisplayPreference.swift
//  simple-recurring-budgets
//

import Foundation

/// How monetary amounts are displayed app-wide.
///
/// Stored in `AppSettings` via `NSUbiquitousKeyValueStore` (key `"currencyDisplay"`).
/// Consumed by `Decimal.formatted(currencyCode:display:locale:)` — the single
/// blessed formatter for all monetary rendering in the app.
enum CurrencyDisplayPreference: String, CaseIterable, Identifiable, Codable, Sendable {
    /// Show only the locale's conventional currency symbol, e.g. "$25.00" or "25,00 €".
    case symbol        = "symbol"
    /// Show only the ISO 4217 code, e.g. "USD 25.00".
    case code          = "code"
    /// Show the ISO code prepended to the symbol form, e.g. "USD $25.00".
    case codeAndSymbol = "codeAndSymbol"

    var id: Self { self }

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

    // MARK: - Prefix

    /// Currency symbol and/or ISO code for `currencyCode` in this display mode — not a full amount string.
    func prefix(for currencyCode: String, locale: Locale = .autoupdatingCurrent) -> String {
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.currencyCode = currencyCode
        fmt.locale = locale
        let symbol = fmt.currencySymbol ?? currencyCode
        switch self {
        case .symbol:        return symbol
        case .code:          return currencyCode
        case .codeAndSymbol: return "\(currencyCode) \(symbol)"
        }
    }
}
