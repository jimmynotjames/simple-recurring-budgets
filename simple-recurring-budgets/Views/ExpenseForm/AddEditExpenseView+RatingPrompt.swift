import SwiftUI

extension AddEditExpenseView {
  /// F-6.03: after a successful Add-mode save, feeds the rating-prompt coordinator its post-save
  /// lifecycle and non-deficit signals. Edit saves and failed saves never reach here.
  func notifyRatingPromptIfNeeded() {
    guard let ratingPrompt,
          let signals = RatingPromptCoordinator.expenseLogSignals(
            isAddMode: !viewModel.isEditing,
            budget: viewModel.budget,
            weekStart: settings.weekStartDay
          )
    else { return }
    ratingPrompt.recordExpenseLogged(
      isActiveBudget: signals.isActiveBudget,
      remainingIsNonNegative: signals.remainingIsNonNegative
    )
  }
}
