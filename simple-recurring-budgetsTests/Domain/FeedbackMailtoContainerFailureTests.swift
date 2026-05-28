import Foundation
@testable import simple_recurring_budgets
import Testing

@Suite("FeedbackMailto.containerFailureURL — payload allow-list")
struct FeedbackMailtoContainerFailureTests {
  @Test("Subject contains the English diagnostic suffix with domain and code")
  func subjectCarriesDiagnosticSuffix() {
    let url = FeedbackMailto.containerFailureURL(
      errorDomain: "NSCocoaErrorDomain",
      errorCode: 134_030
    )
    // Subject is percent-encoded in the URL; decode for the literal check.
    let absolute = url.absoluteString.removingPercentEncoding ?? url.absoluteString
    #expect(absolute.contains(" — container failure (NSCocoaErrorDomain 134030)"))
  }

  @Test("Body contains only domain + code as diagnostic values")
  func bodyAllowList() {
    let url = FeedbackMailto.containerFailureURL(
      errorDomain: "NSCocoaErrorDomain",
      errorCode: 134_030
    )
    let absolute = url.absoluteString.removingPercentEncoding ?? url.absoluteString

    // The two allowed diagnostic values appear.
    #expect(absolute.contains("Error domain: NSCocoaErrorDomain"))
    #expect(absolute.contains("Error code: 134030"))

    // None of the forbidden sentinels appear.
    #expect(!absolute.lowercased().contains("budget_name"))
    #expect(!absolute.lowercased().contains("expense_name"))
    #expect(!absolute.lowercased().contains("amount"))
    #expect(!absolute.lowercased().contains("operation:"))
  }

  @Test("Email recipient is unchanged across mailto variants")
  func recipientMatchesPlainURL() {
    let url = FeedbackMailto.containerFailureURL(errorDomain: "X", errorCode: 0)
    #expect(url.absoluteString.contains("mailto:\(FeedbackMailto.recipient)"))
  }
}
