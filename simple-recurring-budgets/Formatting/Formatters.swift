import Foundation

// MARK: - Money

extension Decimal {
  /// Canonical rendering of a monetary `Decimal` for a Budget's ISO 4217 code: the single blessed path. Pass
  /// `locale` only for deterministic tests.
  ///
  /// `display` controls the currency representation format:
  /// - `.symbol`        → locale's conventional symbol form, e.g. "$25.00", "25,00 €"
  /// - `.code`          → ISO 4217 code in place of symbol, e.g. "USD 25.00"
  /// - `.codeAndSymbol` → code prepended to the symbol form, e.g. "USD $25.00"
  func formatted(
    currencyCode: String,
    display: CurrencyDisplayPreference = .symbol,
    locale: Locale = .autoupdatingCurrent
  ) -> String {
    switch display {
    case .symbol:
      return formatted(.currency(code: currencyCode).locale(locale))
    case .code:
      return formatted(
        .currency(code: currencyCode).presentation(.isoCode).locale(locale)
      )
    case .codeAndSymbol:
      let symbolForm = formatted(.currency(code: currencyCode).locale(locale))
      return "\(currencyCode) \(symbolForm)"
    }
  }
}

// MARK: - Carry-over

/// Sign classification for a signed cumulative carry-over: positive is surplus (under-spent), negative is deficit (over-spent).
enum CarryOverSign { case surplus, deficit, zero }

/// Styling-friendly carry-over components. `amount` is always the magnitude in the budget's currency so
/// views can place the sign/label anywhere (or drop it when `sign == .zero`).
struct CarryOverDisplay: Equatable {
  let amount: String
  let label: String?
  let sign: CarryOverSign
}

enum CarryOverFormatter {
  /// Splits sign from magnitude so views can style the label independently (e.g. color) without re-parsing
  /// formatted strings. Exact copy lives in the String Catalog. `display` defaults to `.symbol`.
  static func display(
    _ amount: Decimal,
    currencyCode: String,
    display: CurrencyDisplayPreference = .symbol,
    locale: Locale = .autoupdatingCurrent
  ) -> CarryOverDisplay {
    let magnitude = abs(amount).formatted(currencyCode: currencyCode, display: display, locale: locale)
    if amount > 0 {
      return CarryOverDisplay(
        amount: magnitude,
        label: String(
          localized: "carryOver.surplus",
          defaultValue: "surplus",
          comment: "Label shown next to a positive carry-over amount (PRD §6.7)"
        ),
        sign: .surplus
      )
    } else if amount < 0 {
      return CarryOverDisplay(
        amount: magnitude,
        label: String(
          localized: "carryOver.deficit",
          defaultValue: "deficit",
          comment: "Label shown next to a negative carry-over amount (PRD §6.7)"
        ),
        sign: .deficit
      )
    } else {
      return CarryOverDisplay(amount: magnitude, label: nil, sign: .zero)
    }
  }
}

// MARK: - Dates (expense list convention)

extension Date {
  /// Expense list row convention: "Today"/"Yesterday" with time when recent, otherwise locale-aware date +
  /// time via `.dateTime`. `reference`, `calendar`, and `locale` are injectable for tests.
  func formattedForExpenseList(
    relativeTo reference: Date = .now,
    calendar: Calendar = .autoupdatingCurrent,
    locale: Locale = .autoupdatingCurrent
  ) -> String {
    var cal = calendar
    cal.locale = locale
    let timeStyle: Date.FormatStyle = .dateTime.hour().minute().locale(locale)
    let timeString = formatted(timeStyle)

    if cal.isDate(self, inSameDayAs: reference) {
      let today = String(
        localized: "date.today",
        defaultValue: "Today",
        comment: "Relative day label used in the expense list for entries on the reference day"
      )
      return "\(today) \(timeString)"
    }

    if let yesterday = cal.date(byAdding: .day, value: -1, to: reference),
       cal.isDate(self, inSameDayAs: yesterday) {
      let yesterdayLabel = String(
        localized: "date.yesterday",
        defaultValue: "Yesterday",
        comment: "Relative day label used in the expense list for entries on the day before the reference day"
      )
      return "\(yesterdayLabel) \(timeString)"
    }

    return formatted(
      .dateTime.year().month().day().hour().minute().locale(locale)
    )
  }
}
