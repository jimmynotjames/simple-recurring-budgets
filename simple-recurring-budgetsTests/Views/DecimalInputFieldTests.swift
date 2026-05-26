@testable import simple_recurring_budgets
import Testing

@Suite("DecimalInputField.isAcceptable — live fraction capping")
struct DecimalInputFieldFractionTests {
  private let dotComma: Set<Character> = [".", ","]

  // MARK: - 0-decimal currencies (JPY, KRW): no fractional entry at all

  @Test func zeroDecimal_acceptsDigits() {
    #expect(DecimalInputField.isAcceptable("1234", maxFractionDigits: 0, separators: dotComma))
    #expect(DecimalInputField.isAcceptable("", maxFractionDigits: 0, separators: dotComma))
  }

  @Test func zeroDecimal_rejectsAnyDecimalSeparator() {
    #expect(!DecimalInputField.isAcceptable("12.", maxFractionDigits: 0, separators: dotComma))
    #expect(!DecimalInputField.isAcceptable("12,5", maxFractionDigits: 0, separators: dotComma))
    #expect(!DecimalInputField.isAcceptable("12.0", maxFractionDigits: 0, separators: dotComma))
  }

  // MARK: - 2-decimal currencies (USD, EUR)

  @Test func twoDecimal_allowsUpToTwoFractionDigits() {
    #expect(DecimalInputField.isAcceptable("12", maxFractionDigits: 2, separators: dotComma))
    #expect(DecimalInputField.isAcceptable("12.", maxFractionDigits: 2, separators: dotComma))
    #expect(DecimalInputField.isAcceptable("12.5", maxFractionDigits: 2, separators: dotComma))
    #expect(DecimalInputField.isAcceptable("12.50", maxFractionDigits: 2, separators: dotComma))
  }

  @Test func twoDecimal_rejectsThirdFractionDigit() {
    #expect(!DecimalInputField.isAcceptable("12.505", maxFractionDigits: 2, separators: dotComma))
  }

  // MARK: - 3-decimal currencies (BHD, KWD)

  @Test func threeDecimal_allowsThreeRejectsFour() {
    #expect(DecimalInputField.isAcceptable("1.234", maxFractionDigits: 3, separators: dotComma))
    #expect(!DecimalInputField.isAcceptable("1.2345", maxFractionDigits: 3, separators: dotComma))
  }

  // MARK: - Locale separator (comma) and edge cases

  @Test func recognizesCommaSeparator() {
    // de_DE / fr_FR style: comma is the decimal separator
    #expect(DecimalInputField.isAcceptable("12,50", maxFractionDigits: 2, separators: dotComma))
    #expect(!DecimalInputField.isAcceptable("12,505", maxFractionDigits: 2, separators: dotComma))
  }

  @Test func rejectsMultipleSeparators() {
    #expect(!DecimalInputField.isAcceptable("1.2.3", maxFractionDigits: 2, separators: dotComma))
  }

  @Test func recognizesArabicDecimalSeparator() {
    let arabic: Set<Character> = [",", "\u{066B}"]
    #expect(!DecimalInputField.isAcceptable("12\u{066B}5", maxFractionDigits: 0, separators: arabic))
    #expect(DecimalInputField.isAcceptable("12\u{066B}5", maxFractionDigits: 2, separators: arabic))
  }
}
