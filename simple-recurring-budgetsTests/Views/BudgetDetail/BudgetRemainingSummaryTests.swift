import Foundation
@testable import simple_recurring_budgets
import Testing

// MARK: - BudgetRemainingSummary.accessibilityLabel

/// Covers all 8 paths of the static a11y label helper (`(isSpecificDates, isOverBudget)` × name/no-name
/// prefix), the `remaining == 0` boundary, the negative-amount sign flip, and the `.preStart`/`.postEnd`
/// inactive reasons.
///
/// Assertions are structural (prefix + substring) so they stay stable under copy and locale changes.
struct BudgetSummaryAccessibilityLabelTests {
  // MARK: - Recurring × under budget

  @Test func recurring_underBudget_withName_prefixesNameAndAnnouncesRemainingPeriod() {
    let label = BudgetRemainingSummary.accessibilityLabel(
      budgetName: "Groceries",
      remaining: 248.50,
      allocation: 400,
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
      allocation: 400,
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
      allocation: 400,
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
      allocation: 400,
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
      allocation: 1000,
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
      allocation: 1000,
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
      allocation: 1000,
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
      allocation: 1000,
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
      allocation: 25,
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
      allocation: 200,
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
      allocation: 200,
      isSpecificDates: false,
      periodInlineLabel: "monthly",
      currencyCode: "USD",
      currencyDisplay: .symbol
    )
    // Body after the name prefix must not start with "-": the helper flips the sign ("$57.25 over budget…").
    let body = label.dropFirst("Foo, ".count)
    #expect(!body.hasPrefix("-"))
    #expect(body.contains("57"))
  }

  // MARK: - Inactive states (preStart, postEnd)

  @Test func preStart_withName_announcesAllocationStartsDate() {
    let startDate = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let label = BudgetRemainingSummary.accessibilityLabel(
      budgetName: "Groceries",
      remaining: 0,
      allocation: 400,
      isSpecificDates: false,
      periodInlineLabel: "monthly",
      currencyCode: "USD",
      currencyDisplay: .symbol,
      inactiveReason: .preStart(startDate: startDate)
    )
    #expect(label.hasPrefix("Groceries, "))
    #expect(label.contains("starts"))
    #expect(label.contains("monthly"))
    #expect(!label.contains("remaining"))
    #expect(!label.contains("over budget"))
    // Allocation, not remaining, drives the announcement.
    #expect(label.contains("400") || label.contains("$400"))
  }

  @Test func preStart_withoutName_omitsPrefix() {
    let startDate = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let label = BudgetRemainingSummary.accessibilityLabel(
      budgetName: nil,
      remaining: 0,
      allocation: 400,
      isSpecificDates: false,
      periodInlineLabel: "monthly",
      currencyCode: "USD",
      currencyDisplay: .symbol,
      inactiveReason: .preStart(startDate: startDate)
    )
    // No name → label must not start with "<name>, ". The formatted date may contain ", " (e.g. "Jun 1, 2026"),
    // so assert the first character is a digit/currency symbol instead of `contains(", ")`.
    let first = label.first ?? " "
    #expect(first.isNumber || first == "$" || first == "€" || first == "£")
    #expect(label.contains("starts"))
  }

  @Test func postEnd_withName_announcesAllocationEndedDate() {
    let endDate = Date(timeIntervalSinceReferenceDate: 900_000_000)
    let label = BudgetRemainingSummary.accessibilityLabel(
      budgetName: "Groceries",
      remaining: 42,
      allocation: 400,
      isSpecificDates: false,
      periodInlineLabel: "monthly",
      currencyCode: "USD",
      currencyDisplay: .symbol,
      inactiveReason: .postEnd(endDate: endDate)
    )
    #expect(label.hasPrefix("Groceries, "))
    #expect(label.contains("ended"))
    #expect(label.contains("monthly"))
    #expect(!label.contains("remaining"))
    #expect(!label.contains("over budget"))
    // Allocation, not the final-period residual remaining, drives the announcement.
    #expect(label.contains("400") || label.contains("$400"))
  }

  @Test func postEnd_withoutName_omitsPrefix() {
    let endDate = Date(timeIntervalSinceReferenceDate: 900_000_000)
    let label = BudgetRemainingSummary.accessibilityLabel(
      budgetName: nil,
      remaining: 42,
      allocation: 400,
      isSpecificDates: false,
      periodInlineLabel: "monthly",
      currencyCode: "USD",
      currencyDisplay: .symbol,
      inactiveReason: .postEnd(endDate: endDate)
    )
    // Same prefix-check rationale as preStart_withoutName_omitsPrefix.
    let first = label.first ?? " "
    #expect(first.isNumber || first == "$" || first == "€" || first == "£")
    #expect(label.contains("ended"))
  }

  // MARK: - Active state (no inactive reason)

  /// Active row (`inactiveReason == nil`) uses `remaining`, not `allocation`, and the on-budget
  /// recurring key — never a `.preStart`/`.postEnd` variant.
  @Test func active_inactiveReasonIsNil_usesRemainingNotAllocation() {
    let label = BudgetRemainingSummary.accessibilityLabel(
      budgetName: "Groceries",
      remaining: 12.50,
      allocation: 400, // intentionally very different from remaining
      isSpecificDates: false,
      periodInlineLabel: "monthly",
      currencyCode: "USD",
      currencyDisplay: .symbol,
      inactiveReason: nil
    )
    #expect(label.hasPrefix("Groceries, "))
    #expect(label.contains("remaining"))
    #expect(label.contains("monthly"))
    #expect(label.contains("period"))
    // Active path announces `remaining` (12.50), never the allocation (400).
    #expect(label.contains("12"))
    #expect(!label.contains("400"))
    // No inactive-state copy.
    #expect(!label.contains("starts"))
    #expect(!label.contains("ended"))
  }

  @Test func paused_fallsThroughToOnBudgetKey() {
    let pausedSince = Date(timeIntervalSinceReferenceDate: 800_500_000)
    let label = BudgetRemainingSummary.accessibilityLabel(
      budgetName: nil,
      remaining: 7.50,
      allocation: 25,
      isSpecificDates: false,
      periodInlineLabel: "daily",
      currencyCode: "USD",
      currencyDisplay: .symbol,
      inactiveReason: .paused(since: pausedSince)
    )
    // Paused reuses the on-budget recurring key; no paused-specific suffix.
    #expect(label.contains("remaining"))
    #expect(label.contains("daily"))
    #expect(!label.contains("starts"))
    #expect(!label.contains("ended"))
  }
}
