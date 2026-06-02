import SwiftUI

extension AddEditExpenseView {
  /// F-6.03: after a successful **Add-mode** save, feed the rating-prompt coordinator
  /// the post-save lifecycle / non-deficit signals so eligibility can advance.
  ///
  /// Edit-mode saves and failed saves never reach here (failures throw before the call
  /// site in `commitSave`). The coordinator only requests a review at a positive,
  /// active, non-deficit moment — see `RatingPromptCoordinator`.
  func notifyRatingPromptIfNeeded() {
    guard let ratingPrompt,
          let signals = RatingPromptCoordinator.expenseLogSignals(
            isAddMode: !viewModel.isEditing,
            budget: viewModel.budget
          )
    else { return }
    ratingPrompt.recordExpenseLogged(
      isActiveBudget: signals.isActiveBudget,
      remainingIsNonNegative: signals.remainingIsNonNegative
    )
  }
}
