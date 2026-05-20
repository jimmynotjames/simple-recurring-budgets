import Foundation
@testable import simple_recurring_budgets
import Testing

// MARK: - BudgetRemainingSummary.accessibilityLabel

/// Tests cover the 8 case paths of the static a11y label helper (4-case switch
/// on `(isSpecificDates, isOverBudget)` × name/no-name prefix), plus the
/// `remaining == 0` boundary and the negative-amount sign-flip.
///
/// Assertions are structural (prefix + substring) rather than full-string
/// equality so they remain stable under copy tweaks and locale changes in the
/// test environment.
struct BudgetSummaryAccessibilityLabelTests {
  // MARK: - Recurring × under budget

  @Test func recurring_underBudget_withName_prefixesNameAndAnnouncesRemainingPeriod() {
    let label = BudgetRemainingSummary.accessibilityLabel(
      budgetName: "Groceries",
      remaining: 248.50,
      isSpecificDates: false,
      periodInlineLabel: "monthly",
      currencyCode: "USD",
      currencyDisplay: .symbol
    )
    #expect(label.hasPrefix("Groceries, "))
    #expect(label.contains("remaining"))
    #expect(label.contains("monthly"))
    #expect(label.contains("period"))
    #expect(!label.contains("over budget"))
  }

  @Test func recurring_underBudget_withoutName_announcesRemainingPeriodOnly() {
    let label = BudgetRemainingSummary.accessibilityLabel(
      budgetName: nil,
      remaining: 248.50,
      isSpecificDates: false,
      periodInlineLabel: "monthly",
      currencyCode: "USD",
      currencyDisplay: .symbol
    )
    #expect(!label.contains(", "))
    #expect(label.contains("remaining"))
    #expect(label.contains("monthly"))
    #expect(label.contains("period"))
    #expect(!label.contains("over budget"))
  }

  // MARK: - Recurring × over budget

  @Test func recurring_overBudget_withName_prefixesNameAndAnnouncesPositiveOverage() {
    let label = BudgetRemainingSummary.accessibilityLabel(
      budgetName: "Groceries",
      remaining: -57.25,
      isSpecificDates: false,
      periodInlineLabel: "monthly",
      currencyCode: "USD",
      currencyDisplay: .symbol
    )
    #expect(label.hasPrefix("Groceries, "))
    #expect(label.contains("over budget"))
    #expect(label.contains("monthly"))
    #expect(label.contains("period"))
    #expect(!label.contains("remaining"))
  }

  @Test func recurring_overBudget_withoutName_announcesPositiveOverage() {
    let label = BudgetRemainingSummary.accessibilityLabel(
      budgetName: nil,
      remaining: -57.25,
      isSpecificDates: false,
      periodInlineLabel: "monthly",
      currencyCode: "USD",
      currencyDisplay: .symbol
    )
    #expect(!label.contains(", "))
    #expect(label.contains("over budget"))
    #expect(label.contains("monthly"))
    #expect(label.contains("period"))
    #expect(!label.contains("remaining"))
  }

  // MARK: - Specific Dates × under budget

  @Test func specificDates_underBudget_withName_prefixesNameAndAnnouncesInlineDescriptor() {
    let label = BudgetRemainingSummary.accessibilityLabel(
      budgetName: "Vacation",
      remaining: 941.00,
      isSpecificDates: true,
      periodInlineLabel: "in this window",
      currencyCode: "USD",
      currencyDisplay: .symbol
    )
    #expect(label.hasPrefix("Vacation, "))
    #expect(label.contains("remaining"))
    #expect(label.contains("in this window"))
    // Specific Dates grammar omits the trailing "period" wrapper.
    #expect(!label.contains("this monthly period"))
    #expect(!label.contains("over budget"))
  }

  @Test func specificDates_underBudget_withoutName_announcesInlineDescriptorOnly() {
    let label = BudgetRemainingSummary.accessibilityLabel(
      budgetName: nil,
      remaining: 941.00,
      isSpecificDates: true,
      periodInlineLabel: "in this window",
      currencyCode: "USD",
      currencyDisplay: .symbol
    )
    #expect(!label.contains(", "))
    #expect(label.contains("remaining"))
    #expect(label.contains("in this window"))
    #expect(!label.contains("over budget"))
  }

  // MARK: - Specific Dates × over budget

  @Test func specificDates_overBudget_withName_prefixesNameAndAnnouncesPositiveOverage() {
    let label = BudgetRemainingSummary.accessibilityLabel(
      budgetName: "Vacation",
      remaining: -120.00,
      isSpecificDates: true,
      periodInlineLabel: "in this window",
      currencyCode: "USD",
      currencyDisplay: .symbol
    )
    #expect(label.hasPrefix("Vacation, "))
    #expect(label.contains("over budget"))
    #expect(label.contains("in this window"))
    #expect(!label.contains("remaining"))
  }

  @Test func specificDates_overBudget_withoutName_announcesPositiveOverage() {
    let label = BudgetRemainingSummary.accessibilityLabel(
      budgetName: nil,
      remaining: -120.00,
      isSpecificDates: true,
      periodInlineLabel: "in this window",
      currencyCode: "USD",
      currencyDisplay: .symbol
    )
    #expect(!label.contains(", "))
    #expect(label.contains("over budget"))
    #expect(label.contains("in this window"))
    #expect(!label.contains("remaining"))
  }

  // MARK: - Edge cases

  @Test func zeroRemaining_classifiedAsRemainingNotOverBudget() {
    let label = BudgetRemainingSummary.accessibilityLabel(
      budgetName: nil,
      remaining: 0,
      isSpecificDates: false,
      periodInlineLabel: "daily",
      currencyCode: "USD",
      currencyDisplay: .symbol
    )
    #expect(label.contains("remaining"))
    #expect(!label.contains("over budget"))
  }

  @Test func namePrefix_usesCommaAndSpaceVerbatim() {
    let label = BudgetRemainingSummary.accessibilityLabel(
      budgetName: "Foo",
      remaining: 100,
      isSpecificDates: false,
      periodInlineLabel: "weekly",
      currencyCode: "USD",
      currencyDisplay: .symbol
    )
    #expect(label.hasPrefix("Foo, "))
  }

  @Test func overBudget_formattedAmountIsPositive() {
    let label = BudgetRemainingSummary.accessibilityLabel(
      budgetName: "Foo",
      remaining: -57.25,
      isSpecificDates: false,
      periodInlineLabel: "monthly",
      currencyCode: "USD",
      currencyDisplay: .symbol
    )
    // The body after the name prefix must not begin with a minus sign — the
    // helper flips the sign so the announcement reads "$57.25 over budget…",
    // not "-$57.25 over budget…".
    let body = label.dropFirst("Foo, ".count)
    #expect(!body.hasPrefix("-"))
    #expect(body.contains("57"))
  }
}
