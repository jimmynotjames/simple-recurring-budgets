import SwiftData
import SwiftUI

// MARK: - SaveErrorState

/// State driving the standard save-error alert presented over any screen that
/// performs an interactive `context.save()`. Bound via `.saveErrorAlert(_:)`.
///
/// Per the `persistence-error-handling` capability:
/// - The alert appears whenever an interactive save throws a `PersistenceError`.
/// - **Retry** re-runs `retry`. The state is *not* cleared by Retry — the
///   caller's success path is responsible for clearing it (typically by
///   re-setting the bound `@State` to `nil` after the next successful save,
///   handled by `setForFailure` / `clear` here).
/// - **Cancel** clears the state and **rolls back the context's pending
///   changes** (the failed mutation), then leaves the host sheet open. Without
///   the rollback the abandoned mutation lingers unsaved in the main context —
///   the UI diverges from the store (e.g. a swipe-deleted row stays hidden),
///   tapping Save again on an Add sheet would stack a second pending insert,
///   and the main context's default autosave could silently commit the
///   "cancelled" change later. Spec: "no data is persisted" on cancel.
/// - **Send Feedback** (escalated path) abandons the operation the same way —
///   it also rolls back before clearing.
/// - When `consecutiveFailureCount >= 3` the alert also exposes **Send Feedback**.
struct SaveErrorState: Identifiable, Equatable {
  let id = UUID()
  let operation: PersistenceOperation
  let errorDomain: String
  let errorCode: Int
  var consecutiveFailureCount: Int
  /// Closure to re-attempt the failed operation. Not part of `Equatable`.
  let retry: () -> Void

  /// Threshold per spec: once we hit three consecutive failures of the same
  /// operation, the alert escalates to expose **Send Feedback**.
  static let escalationThreshold = 3

  var shouldOfferFeedback: Bool {
    consecutiveFailureCount >= Self.escalationThreshold
  }

  static func == (lhs: SaveErrorState, rhs: SaveErrorState) -> Bool {
    lhs.id == rhs.id
      && lhs.operation == rhs.operation
      && lhs.errorDomain == rhs.errorDomain
      && lhs.errorCode == rhs.errorCode
      && lhs.consecutiveFailureCount == rhs.consecutiveFailureCount
  }
}

// MARK: - Reducer helpers

extension SaveErrorState? {
  /// Apply a fresh failure to the bound state. Increments the count when the
  /// operation matches the previous failure; otherwise resets to 1.
  mutating func setForFailure(_ error: PersistenceError, retry: @escaping () -> Void) {
    let nextCount: Int = {
      guard let prev = self, prev.operation == error.operation else { return 1 }
      return prev.consecutiveFailureCount + 1
    }()
    self = SaveErrorState(
      operation: error.operation,
      errorDomain: error.errorDomain,
      errorCode: error.errorCode,
      consecutiveFailureCount: nextCount,
      retry: retry
    )
  }

  /// Clear the alert (called by callers on successful save / cancel).
  mutating func clear() {
    self = nil
  }
}

// MARK: - View modifier

extension View {
  /// Presents the standard save-error alert when `state` is non-nil.
  ///
  /// The bound state is cleared by the alert's Cancel / Send Feedback buttons,
  /// which also roll back the model context's pending (failed) changes — see
  /// the abandonment rationale on `SaveErrorState`. Retry invokes `state.retry`
  /// but leaves the state and the pending changes in place — the caller's
  /// success branch should clear it after the next successful save.
  ///
  /// Requires a `.modelContainer` ancestor (true for every production screen
  /// and preview that performs saves).
  func saveErrorAlert(_ state: Binding<SaveErrorState?>) -> some View {
    modifier(SaveErrorAlertModifier(state: state))
  }
}

private struct SaveErrorAlertModifier: ViewModifier {
  @Binding var state: SaveErrorState?
  @Environment(\.openURL) private var openURL
  @Environment(\.modelContext) private var context

  func body(content: Content) -> some View {
    content.alert(
      String(
        localized: "saveError.alert.title",
        defaultValue: "Couldn't save",
        comment: "Title of the alert shown when a SwiftData save fails during an interactive action like Save or Delete."
      ),
      isPresented: Binding(
        get: { state != nil },
        set: { if !$0 { state = nil } }
      ),
      presenting: state
    ) { current in
      Button(String(
        localized: "saveError.alert.retry",
        defaultValue: "Retry",
        comment: "Button on the save-failure alert that re-attempts the failed save."
      )) {
        current.retry()
      }

      if current.shouldOfferFeedback {
        Button(String(
          localized: "saveError.alert.sendFeedback",
          defaultValue: "Send Feedback",
          comment: "Button on the save-failure alert that opens an email to the developer prefilled with non-PII error context. Only appears after three consecutive failures."
        )) {
          let url = FeedbackMailto.diagnosticURL(
            operation: current.operation,
            errorDomain: current.errorDomain,
            errorCode: current.errorCode
          )
          openURL(url)
          // Abandoning the operation — discard the failed mutation so it can't
          // linger pending and commit later (see `SaveErrorState` doc).
          context.rollback()
          state = nil
        }
      }

      Button(String(
        localized: "saveError.alert.cancel",
        defaultValue: "Cancel",
        comment: "Button that dismisses the save-failure alert without retrying. The host sheet stays open with the user's input intact."
      ), role: .cancel) {
        // Abandoning the operation — discard the failed mutation so the UI and
        // store agree and autosave can't commit it later (see `SaveErrorState`).
        context.rollback()
        state = nil
      }
    } message: { current in
      if current.shouldOfferFeedback {
        Text(String(
          localized: "saveError.alert.message.escalated",
          defaultValue: "We couldn't save your changes. Your information is still here — try again, or send us the error details so we can help.",
          comment: "Body shown on the save-failure alert after three consecutive failures of the same operation."
        ))
      } else {
        Text(String(
          localized: "saveError.alert.message",
          defaultValue: "Something went wrong saving your changes. Your information is still here — please try again.",
          comment: "Body shown on the save-failure alert for the first two attempts. Reassures the user their input is intact and offers a retry."
        ))
      }
    }
  }
}
