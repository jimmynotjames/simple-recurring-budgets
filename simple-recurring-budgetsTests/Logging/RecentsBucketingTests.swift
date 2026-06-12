import Foundation
@testable import simple_recurring_budgets
import Testing

/// Direct tests for the F-7.04 Recents bucketing helpers. The boundaries are part of the
/// analytics contract (see `docs/analytics-spec.md` §10.1) — a silent bucket change would
/// shift every dashboard reading downstream, so we lock them down here.
struct RecentsBucketingTests {
  // MARK: - recentsVisibleCountBucket

  @Test func visibleCount_zero() {
    #expect(recentsVisibleCountBucket(0) == "0")
  }

  @Test func visibleCount_negative_foldsToZero() {
    #expect(recentsVisibleCountBucket(-3) == "0")
  }

  @Test func visibleCount_one() {
    #expect(recentsVisibleCountBucket(1) == "1")
  }

  @Test func visibleCount_twoAndThree_collapse() {
    #expect(recentsVisibleCountBucket(2) == "2-3")
    #expect(recentsVisibleCountBucket(3) == "2-3")
  }

  @Test func visibleCount_fourThroughSeven_collapse() {
    #expect(recentsVisibleCountBucket(4) == "4-7")
    #expect(recentsVisibleCountBucket(5) == "4-7")
    #expect(recentsVisibleCountBucket(6) == "4-7")
    #expect(recentsVisibleCountBucket(7) == "4-7")
  }

  @Test func visibleCount_eightAndBeyond_collapse() {
    // Open-ended top bucket: the 30-tile display cap means counts 16-30 are real,
    // and they all land in "8+" alongside 8-15.
    #expect(recentsVisibleCountBucket(8) == "8+")
    #expect(recentsVisibleCountBucket(15) == "8+")
    #expect(recentsVisibleCountBucket(30) == "8+") // full display-capped row
    #expect(recentsVisibleCountBucket(100) == "8+") // beyond the cap, still saturates
  }

  // MARK: - recentsTapPositionBucket

  @Test func tapPosition_zero() {
    #expect(recentsTapPositionBucket(0) == "0")
  }

  @Test func tapPosition_negative_foldsToZero() {
    #expect(recentsTapPositionBucket(-1) == "0")
  }

  @Test func tapPosition_one_isItsOwnBucket() {
    // Kept distinct from 0 because the product question "do users overwhelmingly tap
    // the FIRST tile?" depends on keeping these two buckets separate.
    #expect(recentsTapPositionBucket(1) == "1")
  }

  @Test func tapPosition_twoThroughFour_collapse() {
    #expect(recentsTapPositionBucket(2) == "2-4")
    #expect(recentsTapPositionBucket(3) == "2-4")
    #expect(recentsTapPositionBucket(4) == "2-4")
  }

  @Test func tapPosition_fiveAndBeyond_collapse() {
    #expect(recentsTapPositionBucket(5) == "5+")
    #expect(recentsTapPositionBucket(14) == "5+")
    #expect(recentsTapPositionBucket(999) == "5+")
  }

  // MARK: - nameQueryLengthBucket

  @Test func queryLength_zero() {
    #expect(nameQueryLengthBucket(0) == "0")
  }

  @Test func queryLength_negative_foldsToZero() {
    #expect(nameQueryLengthBucket(-1) == "0")
  }

  @Test func queryLength_oneAndTwo_collapse() {
    #expect(nameQueryLengthBucket(1) == "1-2")
    #expect(nameQueryLengthBucket(2) == "1-2")
  }

  @Test func queryLength_threeAndBeyond_collapse() {
    #expect(nameQueryLengthBucket(3) == "3+")
    #expect(nameQueryLengthBucket(10) == "3+")
    #expect(nameQueryLengthBucket(100) == "3+")
  }
}
