import XCTest

/// TEMPORARY (#364): CI repro loop for the testReorderBudgets crash. Do not merge.
/// Repeats testReorderBudgets' exact drag from a fresh launch each iteration, classifies the
/// outcome, and on any non-ok outcome tries the second drag that #359's retry does. Fails at the
/// end if anything was off, so CI uploads the result bundle.
@MainActor
final class Repro364Tests: XCTestCase {
  private static let iterations = 25

  private enum Outcome: String {
    case ok, notRegistered, corrupted, crashedOnFirstDrag, crashedOnSecondDrag, secondDragSurvived
  }

  func testReorderLoop() {
    continueAfterFailure = true
    var outcomes: [String] = []
    var anomalies = 0
    for iteration in 0 ..< Self.iterations {
      XCTContext.runActivity(named: "iteration \(iteration)") { _ in
        let result = runIteration(iteration)
        outcomes.append("\(iteration): \(result.outcome.rawValue) | \(result.detail)")
        if result.outcome != .ok {
          anomalies += 1
        }
      }
    }
    let summary = outcomes.joined(separator: "\n")
    print("REPRO364 SUMMARY (\(anomalies) anomalies of \(Self.iterations))\n\(summary)")
    let attachment = XCTAttachment(string: summary)
    attachment.name = "repro364-summary"
    attachment.lifetime = .keepAlways
    add(attachment)
    if anomalies > 0 {
      XCTFail("REPRO364: \(anomalies) anomalies of \(Self.iterations)\n\(summary)")
    }
  }

  private func runIteration(_ iteration: Int) -> (outcome: Outcome, detail: String) {
    let app = makeApp(seedBudgets: ["Alpha", "Bravo", "Charlie"])
    app.launchEnvironment["REPRO364_ITERATION"] = "\(iteration)"
    app.launch()
    let budgets = BudgetsScreen(app: app)
    guard budgets.budgetRow(named: "Charlie").waitForExistence(timeout: 5) else {
      return (.corrupted, "seed rows never appeared")
    }
    let seed = order(budgets)
    budgets.editButton.tap()
    let fromCell = app.cells.element(boundBy: 2)
    let toCell = app.cells.element(boundBy: 0)
    guard fromCell.waitForExistence(timeout: 2) else { return (.corrupted, "no cell 2 in edit mode") }
    let cell0Before = toCell.frame
    let cell2Before = fromCell.frame
    let grabber = fromCell.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5))
    let target = toCell.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.05))
    NSLog("REPRO364 test iteration %d drag start", iteration)
    grabber.press(forDuration: 1.0, thenDragTo: target, withVelocity: .slow, thenHoldForDuration: 0.5)
    NSLog("REPRO364 test iteration %d drag end", iteration)
    guard app.state == .runningForeground else {
      return (.crashedOnFirstDrag, "seed \(seed) cell0 \(cell0Before) cell2 \(cell2Before)")
    }
    let cell0AfterDrag = app.cells.element(boundBy: 0).frame
    let afterDragShot = XCTAttachment(screenshot: app.screenshot())
    app.buttons["Done"].tap()
    guard app.state == .runningForeground else {
      return (.crashedOnFirstDrag, "after Done; seed \(seed)")
    }
    let afterDone = order(budgets)
    var detail = "seed \(seed) cell0 \(cell0Before.minY)->\(cell0AfterDrag.minY) after \(afterDone)"
    let outcome: Outcome = if afterDone.names == ["Charlie", "Alpha", "Bravo"] {
      .ok
    } else if afterDone.names == ["Alpha", "Bravo", "Charlie"] {
      .notRegistered
    } else {
      .corrupted
    }
    guard outcome != .ok else { return (.ok, detail) }

    afterDragShot.name = "iteration \(iteration) after first drag"
    afterDragShot.lifetime = .keepAlways
    add(afterDragShot)
    let afterDoneShot = XCTAttachment(screenshot: app.screenshot())
    afterDoneShot.name = "iteration \(iteration) after Done (\(outcome.rawValue))"
    afterDoneShot.lifetime = .keepAlways
    add(afterDoneShot)

    // The second drag, as #359's retry loop does it.
    budgets.editButton.tap()
    let fromCell2 = app.cells.element(boundBy: 2)
    let toCell2 = app.cells.element(boundBy: 0)
    guard fromCell2.waitForExistence(timeout: 2) else { return (outcome, detail + "; no cell 2 on second drag") }
    detail += "; second drag cell0 \(toCell2.frame.minY) cell2 \(fromCell2.frame.minY)"
    NSLog("REPRO364 test iteration %d second drag start", iteration)
    fromCell2.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).press(
      forDuration: 1.0,
      thenDragTo: toCell2.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.05)),
      withVelocity: .slow,
      thenHoldForDuration: 0.5
    )
    NSLog("REPRO364 test iteration %d second drag end", iteration)
    guard app.state == .runningForeground else {
      return (.crashedOnSecondDrag, detail + " (first: \(outcome.rawValue))")
    }
    return (.secondDragSurvived, detail + " (first: \(outcome.rawValue))")
  }

  private func order(_ budgets: BudgetsScreen) -> (names: [String], minYs: [Int]) {
    let rows = ["Alpha", "Bravo", "Charlie"].map { ($0, budgets.budgetRow(named: $0).frame.minY) }
    let sorted = rows.sorted { $0.1 < $1.1 }
    return (sorted.map(\.0), sorted.map { Int($0.1) })
  }
}
