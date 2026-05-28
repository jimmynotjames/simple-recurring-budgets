import Foundation

/// Builders for the project's "Send Feedback" `mailto:` URL.
///
/// One canonical builder is used by both the Settings "Send Feedback" link
/// and the persistence-save error alert's escalated CTA. The diagnostic
/// variant appends *only* the operation identifier and the error domain/code
/// to the body — never any user data — per the
/// `persistence-error-handling` capability's payload allow-list.
enum FeedbackMailto {
  static let recipient = "jimmyho.appfeedback@gmail.com"
  static let defaultSubject = "Budgets app feedback"

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
  static func diagnosticURL(
    operation: PersistenceOperation,
    errorDomain: String,
    errorCode: Int
  ) -> URL {
    let subject = "\(defaultSubject) — save failure (\(operation.rawValue))"
    let body = """
    A save in the app failed repeatedly. Diagnostic context (no personal data):

    Operation: \(operation.rawValue)
    Error domain: \(errorDomain)
    Error code: \(errorCode)

    Please describe what you were doing when this happened:

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
