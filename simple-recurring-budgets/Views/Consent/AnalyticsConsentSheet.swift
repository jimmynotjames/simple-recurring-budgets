import SwiftUI

/// First-run analytics consent sheet, shown once in strict-opt-in jurisdictions
/// after the user creates their first Budget (§7.2 analytics-spec.md).
///
/// **Accept** — sets `analyticsOptIn = true`, fires `analytics_consent_changed`,
/// then dismisses.
///
/// **Decline** — sets `analyticsOptIn = false`, dismisses. The SDK has not been
/// initialized so no event is sent (there is no live session to record on).
///
/// **Swipe-to-dismiss** — treated as Decline per §7.2: `analyticsOptIn = false`.
struct AnalyticsConsentSheet: View {
  @Environment(AppSettings.self) private var settings
  @Environment(\.analytics) private var analytics
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      VStack(spacing: 24) {
        Spacer()

        Image(systemName: "chart.bar.doc.horizontal")
          .font(.system(size: 56))
          .foregroundStyle(.tint)
          .accessibilityHidden(true)

        VStack(spacing: 12) {
          Text(String(
            localized: "consent.analytics.sheet.title",
            defaultValue: "Help Improve the App?",
            comment: "Title of the first-run analytics consent sheet shown in strict-opt-in jurisdictions after the user creates their first Budget"
          ))
          .font(.title2.bold())
          .multilineTextAlignment(.center)

          Text(String(
            localized: "consent.analytics.sheet.body",
            defaultValue: """
            To help troubleshoot issues and understand usage, this app sends anonymous usage \
            data to backend systems for analysis. Examples of what\u{2019}s shared include budget \
            settings like period, currency code, carry-over on/off, allocation amount, and so on. \
            Never shared: Expense names, amounts, dates, any Apple/iCloud identifiers, any \
            free-text notes or personal information. This decision can be changed at any time \
            on the Settings screen.
            """,
            comment:
            """
            Body of the first-run analytics consent sheet. Describes what is and is not \
            transmitted (mirrors §5 analytics-spec.md). Discloses budget_name and \
            budget_allocation_amount as accepted-risk exceptions per §5.4.
            """
          ))
          .font(.body)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.leading)
        }

        Spacer()

        VStack(spacing: 12) {
          Button {
            accept()
          } label: {
            Text(String(
              localized: "consent.analytics.sheet.accept",
              defaultValue: "Share Anonymous Usage Data",
              comment: "Accept button on the analytics consent sheet; tapping opts the user in to analytics"
            ))
            .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.large)

          Button {
            decline()
          } label: {
            Text(String(
              localized: "consent.analytics.sheet.decline",
              defaultValue: "No Thanks",
              comment: "Decline button on the analytics consent sheet; tapping keeps analytics off"
            ))
            .frame(maxWidth: .infinity)
          }
          .buttonStyle(.bordered)
          .controlSize(.large)
          .tint(.secondary)
        }
      }
      .padding(.horizontal, 24)
      .padding(.bottom, 32)
      .appBackground()
      .navigationBarTitleDisplayMode(.inline)
    }
    // Swipe-to-dismiss is treated as Decline per §7.2.
    .interactiveDismissDisabled(false)
    .onDisappear {
      // If the user swiped down without tapping either button, analyticsOptIn
      // must be set to false so the sheet does not re-appear (analyticsOptInExplicitlySet
      // becomes true). Only write if not already set by the button handlers.
      if !settings.analyticsOptInExplicitlySet {
        settings.analyticsOptIn = false
      }
    }
  }

  // MARK: - Actions

  private func accept() {
    settings.analyticsOptIn = true
    analytics.track(
      AnalyticsEvent.analyticsConsentChanged,
      properties: [AnalyticsProperty.newValue: true]
    )
    dismiss()
  }

  private func decline() {
    settings.analyticsOptIn = false
    dismiss()
  }
}

// MARK: - Preview

#if DEBUG
  #Preview("Strict opt-in jurisdiction") {
    AnalyticsConsentSheet()
      .environment(AppSettings())
  }
#endif
