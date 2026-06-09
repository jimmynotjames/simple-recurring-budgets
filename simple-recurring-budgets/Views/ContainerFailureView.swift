import SwiftUI

/// Recovery surface presented by the `@main` App when both CloudKit-backed
/// and local-only `ModelContainer` creation fail. Replaces the previous
/// `fatalError` crash — see `container-creation-recovery` capability.
///
/// Layout: centered title + body + **Retry** + **Send Feedback**. The
/// underlying `NSError.domain` / `code` are intentionally **not** shown to
/// the user (they appear only in the Send Feedback mailto body for support
/// triage).
struct ContainerFailureView: View {
  let error: ContainerCreationFailure
  let onRetry: () -> Void

  @Environment(\.openURL) private var openURL

  var body: some View {
    VStack(spacing: 24) {
      Spacer()

      VStack(spacing: 12) {
        Image(systemName: "externaldrive.badge.exclamationmark")
          .font(.system(size: 56))
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)

        Text(String(
          localized: "containerFailure.title",
          defaultValue: "Couldn't open your data",
          comment: "Title shown on the recovery screen when the app cannot create its SwiftData container at launch."
        ))
        .font(.title2)
        .fontWeight(.semibold)
        .multilineTextAlignment(.center)

        Text(String(
          localized: "containerFailure.body",
          defaultValue: "Something went wrong loading your budgets. Try again, or send us the details so we can help.",
          comment: """
          Body text on the container-failure recovery screen. \
          Reassures the user, invites Retry or Send Feedback. \
          Should not mention the error code; the diagnostic context \
          is carried in the Send Feedback email body.
          """
        ))
        .font(.body)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
      }
      .accessibilityElement(children: .combine)

      VStack(spacing: 12) {
        Button {
          onRetry()
        } label: {
          Text(String(
            localized: "containerFailure.action.retry",
            defaultValue: "Retry",
            comment: "Primary action button on the container-failure screen. Re-attempts container creation."
          ))
          .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.accentFill)
        .controlSize(.large)
        .accessibilityHint(String(
          localized: "containerFailure.action.retry.accessibilityHint",
          defaultValue: "Tries to open your data again.",
          comment: "VoiceOver hint for the Retry button on the container-failure screen."
        ))

        Button {
          openURL(FeedbackMailto.containerFailureURL(
            errorDomain: error.errorDomain,
            errorCode: error.errorCode
          ))
        } label: {
          Text(String(
            localized: "containerFailure.action.sendFeedback",
            defaultValue: "Send Feedback",
            comment: "Secondary action button on the container-failure screen. Opens an email prefilled with non-PII error details (domain + code)."
          ))
          .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .accessibilityHint(String(
          localized: "containerFailure.action.sendFeedback.accessibilityHint",
          defaultValue: "Opens an email with the error details, no personal data.",
          comment: "VoiceOver hint for the Send Feedback button on the container-failure screen."
        ))
      }

      Spacer()
    }
    .padding(.horizontal, 32)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
  }
}

#if DEBUG
  #Preview("ContainerFailureView") {
    ContainerFailureView(
      error: ContainerCreationFailure(
        errorDomain: "NSCocoaErrorDomain",
        errorCode: 134_030
      ),
      onRetry: {}
    )
  }
#endif
