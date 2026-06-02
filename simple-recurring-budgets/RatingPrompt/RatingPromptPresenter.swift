import StoreKit
import SwiftUI

/// Root-level presenter for the automatic App Store review prompt (F-6.03).
///
/// Hosted once at the app root (above the `NavigationStack` and the centralized Add
/// Expense sheet) so it works regardless of which screen the user returns to — the
/// Budgets list or a Budget detail. When the coordinator has a pending request, the
/// scene is active, and no sheet is presented (the Add Expense sheet has dismissed),
/// it invokes the native `requestReview` and records the requested version. Gating on
/// `router.sheet == nil` is what makes the prompt appear *after* the sheet dismisses,
/// avoiding the sheet-dismissal race. No custom rating UI is presented.
private struct RatingPromptPresenter: ViewModifier {
  @Environment(\.requestReview) private var requestReview
  @Environment(\.scenePhase) private var scenePhase
  @Environment(RatingPromptCoordinator.self) private var coordinator
  @Environment(Router.self) private var router

  func body(content: Content) -> some View {
    content
      .onChange(of: coordinator.isRequestPending) { _, _ in presentIfReady() }
      .onChange(of: router.sheet == nil) { _, _ in presentIfReady() }
      .onChange(of: scenePhase) { _, _ in presentIfReady() }
  }

  private func presentIfReady() {
    guard RatingPromptCoordinator.shouldRequestReview(
      isRequestPending: coordinator.isRequestPending,
      sheetIsPresented: router.sheet != nil,
      sceneIsActive: scenePhase == .active
    ) else { return }
    requestReview()
    coordinator.consumePendingRequest()
  }
}

extension View {
  /// Applies the F-6.03 automatic rating-prompt presenter. Apply once at the app root,
  /// where `Router` and `RatingPromptCoordinator` are in the environment.
  func ratingPromptPresenter() -> some View {
    modifier(RatingPromptPresenter())
  }
}
