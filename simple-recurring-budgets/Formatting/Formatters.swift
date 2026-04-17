//
//  Formatters.swift
//  simple-recurring-budgets
//

import Foundation

// MARK: - Money

extension Decimal {
    /// Canonical rendering of a monetary `Decimal` for a Budget's ISO 4217 code.
    ///
    /// This is the single blessed path for "render a `Decimal` with a Budget's
    /// currency". Pass `locale` only for deterministic tests; the default
    /// adapts to the user's locale.
    func formatted(
        currencyCode: String,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        self.formatted(.currency(code: currencyCode).locale(locale))
    }
}

// MARK: - Carry-over (PRD §6.7)

/// Sign classification for a carry-over amount. PRD §6.7 defines carry-over as
/// a signed cumulative total; positive is surplus (under-spent), negative is
/// deficit (over-spent).
enum CarryOverSign: Sendable { case surplus, deficit, zero }

/// Styling-friendly components for rendering a carry-over amount. `amount` is
/// always the magnitude in the budget's currency so views can place the
/// sign/label anywhere (or drop it entirely when `sign == .zero`).
struct CarryOverDisplay: Equatable, Sendable {
    let amount: String
    let label: String?
    let sign: CarryOverSign
}

enum CarryOverFormatter {
    /// Splits sign from magnitude so views can style the label independently
    /// (e.g. color) without re-parsing formatted strings. Exact copy is a
    /// design choice per PRD §6.7 and lives in the String Catalog (F-3.03).
    static func display(
        _ amount: Decimal,
        currencyCode: String,
        locale: Locale = .autoupdatingCurrent
    ) -> CarryOverDisplay {
        let magnitude = abs(amount).formatted(currencyCode: currencyCode, locale: locale)
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
    /// Convention for the expense list row: "Today"/"Yesterday" with time when
    /// recent, otherwise a locale-aware date + time via `.dateTime`.
    ///
    /// `reference`, `calendar`, and `locale` are injectable for deterministic
    /// tests; callers should use the defaults in production.
    func formattedForExpenseList(
        relativeTo reference: Date = .now,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        var cal = calendar
        cal.locale = locale
        let timeStyle: Date.FormatStyle = .dateTime.hour().minute().locale(locale)
        let timeString = self.formatted(timeStyle)

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

        return self.formatted(
            .dateTime.year().month().day().hour().minute().locale(locale)
        )
    }
}
