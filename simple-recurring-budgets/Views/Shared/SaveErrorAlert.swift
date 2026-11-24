import SwiftData
import SwiftUI

// MARK: - SaveErrorState

/// State for the standard save-error alert shown when an interactive save throws a
/// `PersistenceError`. Bound via `.saveErrorAlert(_:)`.
///
/// - Retry re-runs `retry` and does not clear the state; the caller's success path clears it.
/// - Cancel clears the state and rolls back the context's pending (failed) changes, leaving
///   the host sheet open. Without the rollback the abandoned mutation lingers in the main
///   context: the UI diverges from the store (a swipe-deleted row stays hidden), Save on
///   an Add sheet would stack a second insert, and autosave could later commit the
///   "cancelled" change.
/// - Send Feedback (offered at `consecutiveFailureCount >= 3`) abandons the same way: it
///   rolls back before clearing.
struct SaveErrorState: Identifiable, Equatable {
  let id = UUID()
  let operation: PersistenceOperation
  let errorDomain: String
  let errorCode: Int
  var consecutiveFailureCount: Int
  /// Closure to re-attempt the failed operation. Not part of `Equatable`.
  let retry: () -> Void

  /// Consecutive failures of the same operation before the alert offers Send Feedback.
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
  /// Applies a fresh failure: increments the count if the operation matches the previous
  /// failure, else resets to 1.
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

  /// Clears the alert (on successful save or cancel).
  mutating func clear() {
    self = nil
  }
}

// MARK: - View modifier

extension View {
  /// Presents the standard save-error alert when `state` is non-nil.
  ///
  /// Cancel / Send Feedback clear the state and roll back pending changes (see
  /// `SaveErrorState`); Retry leaves both in place. Requires a `.modelContainer` ancestor.
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
        set: {
          if !$0 {
            state = nil
          }
        }
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
          // Abandon: discard the failed mutation (see `SaveErrorState`).
          context.rollback()
          state = nil
        }
      }

      Button(String(
        localized: "saveError.alert.cancel",
        defaultValue: "Cancel",
        comment: "Button that dismisses the save-failure alert without retrying. The host sheet stays open with the user's input intact."
      ), role: .cancel) {
        // Abandon: discard the failed mutation (see `SaveErrorState`).
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
