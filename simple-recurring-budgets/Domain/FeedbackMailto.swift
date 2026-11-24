import Foundation

/// Builders for the "Send Feedback" `mailto:` URL, shared by the Settings link and the persistence-save
/// error alert's escalated CTA. Diagnostic variants append only the operation identifier and error
/// domain/code, never user data.
///
/// **Localization split.** User-addressed strings (subject, body intro, closing prompt) are localized;
/// developer-only diagnostic labels (`Operation:` / `Error domain:` / `Error code:`) and the "save failure"
/// subject suffix stay English so the maintainer's inbox is consistent across locales.
enum FeedbackMailto {
  static var recipient: String {
    AppConfig.feedbackEmail
  }

  /// Localized subject for the plain Settings → Send Feedback link.
  static var defaultSubject: String {
    String(
      localized: "feedback.email.subject",
      defaultValue: "Wren app feedback",
      comment: "Subject line of the email that opens when the user taps Send Feedback in Settings."
    )
  }

  /// Plain feedback URL (no diagnostic context).
  static var plainURL: URL {
    let subject = defaultSubject
      .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
    // swiftlint:disable:next force_unwrapping
    return URL(string: "mailto:\(recipient)?subject=\(subject)")!
  }

  /// Feedback URL with non-PII diagnostic context in the body: only the `PersistenceOperation` raw value and
  /// `NSError` domain/code, never budget names, amounts, or other user-derived values.
  ///
  /// Localized: subject prefix, body intro, closing prompt. English-only: the `" — save failure (<op>)"`
  /// suffix and the diagnostic labels.
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

  /// Feedback URL for the container-creation failure recovery surface. Body has only the `NSError` domain +
  /// code, no user data or model identifiers.
  ///
  /// Localized: subject prefix, body intro, closing prompt. English-only: the
  /// `" — container failure (<domain> <code>)"` suffix and the diagnostic labels.
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
