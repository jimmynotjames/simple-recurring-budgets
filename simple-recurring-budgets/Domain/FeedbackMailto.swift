import Foundation

/// Builders for the project's "Send Feedback" `mailto:` URL.
///
/// One canonical builder is used by both the Settings "Send Feedback" link
/// and the persistence-save error alert's escalated CTA. The diagnostic
/// variant appends *only* the operation identifier and the error domain/code
/// to the body — never any user data — per the
/// `persistence-error-handling` capability's payload allow-list.
///
/// **Localization split.** The user-addressed strings (subject, body intro,
/// closing prompt) are localized; the developer-only diagnostic labels
/// (`Operation:` / `Error domain:` / `Error code:`) and the "save failure"
/// subject suffix stay in English so the maintainer's inbox is consistent
/// across locales.
enum FeedbackMailto {
  static let recipient = "jimmyho.appfeedback@gmail.com"

  /// Localized subject for the plain Settings → Send Feedback link.
  static var defaultSubject: String {
    String(
      localized: "feedback.email.subject",
      defaultValue: "Budgets app feedback",
      comment: "Subject line of the email that opens when the user taps Send Feedback in Settings."
    )
  }

  /// Plain feedback URL (no diagnostic context). Matches the legacy
  /// `SettingsView.feedbackMailtoURL` exactly.
  static var plainURL: URL {
    let subject = defaultSubject
      .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
    // swiftlint:disable:next force_unwrapping
    return URL(string: "mailto:\(recipient)?subject=\(subject)")!
  }

  /// Feedback URL with a non-PII diagnostic context appended to the body.
  /// The body contains only the `PersistenceOperation` raw value and the
  /// `NSError` domain/code — no budget name, expense field, amount, or
  /// other user-derived value (`persistence-error-handling` spec).
  ///
  /// Localized parts: subject prefix, body intro, closing user prompt.
  /// English-only parts: `" — save failure (<op>)"` subject suffix, and
  /// the `Operation:` / `Error domain:` / `Error code:` diagnostic labels
  /// (developer-only — keeps support triage consistent across locales).
  static func diagnosticURL(
    operation: PersistenceOperation,
    errorDomain: String,
    errorCode: Int
  ) -> URL {
    let subject = "\(defaultSubject) — save failure (\(operation.rawValue))"

    let intro = String(
      localized: "feedback.email.body.intro",
      defaultValue: "A save in the app failed repeatedly. Diagnostic context (no personal data):",
      comment: "First sentence of the auto-filled email body shown when the user taps Send Feedback after a repeated save failure. Reassures them that no personal data is included."
    )
    let prompt = String(
      localized: "feedback.email.body.prompt",
      defaultValue: "Please describe what you were doing when this happened:",
      comment: "Closing prompt at the end of the auto-filled email body, inviting the user to describe what they were doing when the save failed."
    )

    let body = """
    \(intro)

    Operation: \(operation.rawValue)
    Error domain: \(errorDomain)
    Error code: \(errorCode)

    \(prompt)

    """

    let subjectEncoded = subject
      .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
    let bodyEncoded = body
      .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

    // swiftlint:disable:next force_unwrapping
    return URL(
      string: "mailto:\(recipient)?subject=\(subjectEncoded)&body=\(bodyEncoded)"
    )!
  }

  /// Feedback URL for the container-creation failure recovery surface
  /// (`container-creation-recovery` capability). Body contains only the
  /// `NSError` domain + code — no user data, no model identifiers.
  ///
  /// Localized parts: subject prefix, body intro, closing user prompt.
  /// English-only parts: `" — container failure (<domain> <code>)"` subject
  /// suffix and the `Error domain:` / `Error code:` diagnostic labels.
  static func containerFailureURL(
    errorDomain: String,
    errorCode: Int
  ) -> URL {
    let subject = "\(defaultSubject) — container failure (\(errorDomain) \(errorCode))"

    let intro = String(
      localized: "containerFailure.email.body.intro",
      defaultValue: "The app couldn't open your data store. Diagnostic context (no personal data):",
      comment: "First sentence of the auto-filled email body shown when the user taps Send Feedback on the container-creation failure screen. Reassures them that no personal data is included."
    )
    let prompt = String(
      localized: "containerFailure.email.body.prompt",
      defaultValue: "Please describe what was happening on your device when this started:",
      comment: "Closing prompt at the end of the auto-filled email body on the container-failure surface, inviting the user to describe what was happening when the app couldn't open the data store."
    )

    let body = """
    \(intro)

    Error domain: \(errorDomain)
    Error code: \(errorCode)

    \(prompt)

    """

    let subjectEncoded = subject
      .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
    let bodyEncoded = body
      .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

    // swiftlint:disable:next force_unwrapping
    return URL(
      string: "mailto:\(recipient)?subject=\(subjectEncoded)&body=\(bodyEncoded)"
    )!
  }
}
