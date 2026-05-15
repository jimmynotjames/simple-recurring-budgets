import Foundation
@testable import simple_recurring_budgets
import Testing

struct CurrentPeriodSpilloverTests {
  @Test func ordinarySlack_spilloverIsZero() {
    // 0 ≤ remaining ≤ effectiveAllocation
    #expect(currentPeriodSpillover(remaining: 10, effectiveAllocation: 20, lifecycleState: .active) == 0)
    #expect(currentPeriodSpillover(remaining: 0, effectiveAllocation: 20, lifecycleState: .active) == 0)
    #expect(currentPeriodSpillover(remaining: 20, effectiveAllocation: 20, lifecycleState: .active) == 0)
  }

  @Test func overspend_spilloverNegative() {
    let spillover = currentPeriodSpillover(remaining: -5, effectiveAllocation: 20, lifecycleState: .active)
    #expect(spillover == -5)
  }

  @Test func addFundsExcess_spilloverPositive() {
    // remaining = 50, allocation = 20 → excess = 30
    let spillover = currentPeriodSpillover(remaining: 50, effectiveAllocation: 20, lifecycleState: .active)
    #expect(spillover == 30)
  }

  @Test func postEnd_symmetric_entireRemainingFoldsIn() {
    #expect(currentPeriodSpillover(remaining: 8, effectiveAllocation: 20, lifecycleState: .postEnd) == 8)
    #expect(currentPeriodSpillover(remaining: -3, effectiveAllocation: 20, lifecycleState: .postEnd) == -3)
  }

  @Test func preStart_spilloverIsZero() {
    #expect(currentPeriodSpillover(remaining: 0, effectiveAllocation: 20, lifecycleState: .preStart) == 0)
  }

  @Test func paused_spilloverIsZero() {
    #expect(currentPeriodSpillover(remaining: 0, effectiveAllocation: 20, lifecycleState: .paused) == 0)
  }
}
