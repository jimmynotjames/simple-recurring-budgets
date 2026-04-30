import Foundation

/// Used by `AddEditExpenseView`'s Amount field to allow blank input to map to `Decimal?` rather than `0`.
///
/// The same `ParseableFormatStyle` is reused by `AddEditBudgetView`'s Allocation field. Maps between
/// `Decimal?` and a plain numeric string: empty or whitespace-only input parses to `nil`; otherwise parses
/// with `Locale.current`.
struct OptionalDecimalFormatStyle: ParseableFormatStyle {
  typealias FormatInput = Decimal?
  typealias FormatOutput = String

  func format(_ value: Decimal?) -> String {
    guard let value else { return "" }
    return value.formatted(.number.precision(.fractionLength(0...2)))
  }

  var parseStrategy: OptionalDecimalParseStrategy {
    OptionalDecimalParseStrategy()
  }
}

/// Parse strategy paired with ``OptionalDecimalFormatStyle``.
struct OptionalDecimalParseStrategy: ParseStrategy {
  typealias ParseInput = String
  typealias ParseOutput = Decimal?

  func parse(_ value: String) throws -> Decimal? {
    let trimmed = value.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return nil }
    guard let decimal = Decimal(string: trimmed, locale: .current) else {
      throw CocoaError(.formatting)
    }
    return decimal
  }
}
