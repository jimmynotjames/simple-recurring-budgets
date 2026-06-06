import CloudKit
import OSLog
import StoreKit
import SwiftUI

// MARK: - AppInfo

private enum AppInfo {
  // TODO: Replace with real privacy policy URL before launch.
  static let privacyPolicyURL = "https://example.com/privacy"
}

// MARK: - SettingsView

struct SettingsView: View {
  @Environment(AppSettings.self) private var settings
  @Environment(SyncStatus.self) private var syncStatus
  @Environment(\.analytics) private var analytics
  @Environment(\.dismiss) private var dismiss
  @Environment(\.requestReview) private var requestReview

  /// Holds the user's pending week-start selection until confirmed (F-5.01).
  @State private var pendingWeekStart: Weekday? = nil

  private var appVersion: String {
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
  }

  private var buildNumber: String {
    Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
  }

  /// Localized "Debug" marker appended to the version row in development builds,
  /// so the local build number (always `1` unless a release was cut — see
  /// fastlane `set_project_build_number`) isn't mistaken for the live TestFlight
  /// build. Returns `nil` in Release. Also suppressed during App Store screenshot
  /// capture (`SCREENSHOT_SYNC_OK`, set only by the `AppStoreScreenshots` UI test,
  /// which builds in Debug) so the marker never leaks into marketing screenshots —
  /// same screenshot-suppression flag used in `simple_recurring_budgetsApp`.
  private var debugBadge: String? {
    #if DEBUG
      guard ProcessInfo.processInfo.environment["SCREENSHOT_SYNC_OK"] != "1" else { return nil }
      return String(
        localized: "settings.version.debugBadge",
        defaultValue: "Debug",
        comment: "Badge appended to the version/build string in development (Debug) builds so the local build number is not mistaken for a TestFlight/App Store build. Never shown in Release or in App Store screenshots."
      )
    #else
      return nil
    #endif
  }

  /// VoiceOver copy for the version row, with the `debugBadge` word appended in
  /// development builds so assistive tech announces the Debug marker too.
  private var versionAccessibilityLabel: String {
    let base = String(
      localized: "settings.version.accessibilityLabel",
      defaultValue: "Version \(appVersion), build \(buildNumber)",
      comment: "VoiceOver label for the app version row; arguments are the version string and build number"
    )
    guard let badge = debugBadge else { return base }
    return "\(base), \(badge)"
  }

  var body: some View {
    @Bindable var settings = settings
    NavigationStack {
      Form {
        budgetsSection(carryOverOn: $settings.defaultCarryOverEnabled)
        calendarSection(currentDay: settings.weekStartDay)
        displaySection(currencyDisplay: $settings.currencyDisplay)
        iCloudSection
        analyticsSection
        supportSection
        aboutSection
      }
      .scrollContentBackground(.hidden)
      .navigationTitle(String(
        localized: "settings.navigationTitle",
        defaultValue: "Settings",
        comment: "Navigation bar title for the Settings sheet"
      ))
      .navigationBarTitleDisplayMode(.inline)
      .appBackground()
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button(String(
            localized: "settings.done",
            defaultValue: "Done",
            comment: "Button that dismisses the Settings sheet"
          )) {
            dismiss()
          }
        }
      }
      .alert(
        String(
          localized: "settings.weekStart.alert.title",
          defaultValue: "Change Start of Week?",
          comment: "Title of the confirmation alert shown before applying a week-start day change"
        ),
        isPresented: Binding(
          get: { pendingWeekStart != nil },
          set: { if !$0 { pendingWeekStart = nil } }
        )
      ) {
        Button(String(
          localized: "settings.weekStart.alert.confirm",
          defaultValue: "Change",
          comment: "Confirm button in the week-start day change alert"
        )) {
          if let day = pendingWeekStart {
            let oldDay = settings.weekStartDay
            settings.weekStartDay = day
            analytics.track(
              AnalyticsEvent.settingChanged,
              properties: [
                AnalyticsProperty.settingName: "week_start_day",
                AnalyticsProperty.newValue: day.analyticsValue,
                AnalyticsProperty.oldValue: oldDay.analyticsValue,
              ]
            )
          }
          pendingWeekStart = nil
        }
        Button(String(
          localized: "settings.weekStart.alert.cancel",
          defaultValue: "Cancel",
          comment: "Cancel button in the week-start day change alert"
        ), role: .cancel) {
          pendingWeekStart = nil
        }
      } message: {
        if let day = pendingWeekStart {
          Text(String(
            localized: "settings.weekStart.alert.message",
            defaultValue: "Changing to \(weekdayName(day)) will immediately affect all weekly and biweekly budgets.",
            comment: "Alert body for the week-start day change; argument is the name of the newly selected weekday"
          ))
        }
      }
      .task { await loadICloudStatus() }
      .task { await observeAccountChanges() }
      .task { analytics.track(AnalyticsEvent.settingsOpened) }
    }
  }

  // MARK: - Sections

  private func budgetsSection(carryOverOn: Binding<Bool>) -> some View {
    Section {
      Toggle(
        String(
          localized: "settings.carryOver.toggle",
          defaultValue: "Carry-Over",
          comment: "Toggle label for the default carry-over setting in Settings"
        ),
        isOn: Binding(
          get: { carryOverOn.wrappedValue },
          set: { newValue in
            let oldValue = carryOverOn.wrappedValue
            carryOverOn.wrappedValue = newValue
            analytics.track(
              AnalyticsEvent.settingChanged,
              properties: [
                AnalyticsProperty.settingName: "default_carry_over_enabled",
                AnalyticsProperty.newValue: newValue,
                AnalyticsProperty.oldValue: oldValue,
              ]
            )
          }
        )
      )
      .tint(.accentColor) // Toggle doesn't pick up AccentColor automatically.
      .accessibilityHint(String(
        localized: "settings.carryOver.toggle.accessibilityHint",
        defaultValue: "Sets whether carry-over is on by default when creating a new budget",
        comment: "VoiceOver hint for the default carry-over toggle in Settings"
      ))
      .listRowBackground(Color("CellBackground"))
    } header: {
      Text(String(
        localized: "settings.section.budgets",
        defaultValue: "Budgets",
        comment: "Settings section header for budget-related defaults"
      ))
    } footer: {
      Text(String(
        localized: "settings.carryOver.toggle.footer",
        defaultValue: "Tracks surplus or deficit over time. Default setting for new budgets. Existing budgets are not affected.",
        comment: "Explanatory footer below the default carry-over toggle in Settings"
      ))
    }
  }

  private func calendarSection(currentDay: Weekday) -> some View {
    Section {
      Picker(
        String(
          localized: "settings.weekStart.label",
          defaultValue: "Week Starts On",
          comment: "Label for the week-start day picker in Settings"
        ),
        selection: Binding(
          get: { currentDay },
          set: { new in
            guard new != currentDay else { return }
            pendingWeekStart = new
          }
        )
        // setting_changed for week_start_day fires on confirmation (via alert confirm handler).
        // See the alert confirm button below.
      ) {
        ForEach(Weekday.allCases) { day in
          Text(weekdayName(day)).tag(day)
        }
      }
      .pickerStyle(.menu)
      .accessibilityHint(String(
        localized: "settings.weekStart.accessibilityHint",
        defaultValue: "Changing this affects all weekly and biweekly budgets",
        comment: "VoiceOver hint for the week-start day picker in Settings"
      ))
      .listRowBackground(Color("CellBackground"))
    } header: {
      Text(String(
        localized: "settings.section.calendar",
        defaultValue: "Calendar",
        comment: "Settings section header for calendar preferences"
      ))
    }
  }

  private func displaySection(currencyDisplay: Binding<CurrencyDisplayPreference>) -> some View {
    Section {
      Picker(
        String(
          localized: "settings.currencyDisplay.label",
          defaultValue: "Currency Display",
          comment: "Label for the currency display format picker in Settings"
        ),
        selection: Binding(
          get: { currencyDisplay.wrappedValue },
          set: { newValue in
            let oldValue = currencyDisplay.wrappedValue
            currencyDisplay.wrappedValue = newValue
            analytics.track(
              AnalyticsEvent.settingChanged,
              properties: [
                AnalyticsProperty.settingName: "currency_display_preference",
                AnalyticsProperty.newValue: newValue.analyticsValue,
                AnalyticsProperty.oldValue: oldValue.analyticsValue,
              ]
            )
          }
        )
      ) {
        // F-2.05 acceptance: each row reads "<localized option label> — <locale-aware example>",
        // not the example alone. The example is derived live from the user's locale.
        ForEach(CurrencyDisplayPreference.allCases) { option in
          Text(String(
            localized: "settings.currencyDisplay.option.row",
            defaultValue: "\(option.label) — \(option.example())",
            comment:
            "Composite Settings picker row text per F-2.05. First argument is the localized option label (Symbol / Code / Code + Symbol); second is a locale-aware example such as \"$25.00\"."
          ))
          .tag(option)
        }
      }
      .pickerStyle(.menu)
      .listRowBackground(Color("CellBackground"))
    } header: {
      Text(String(
        localized: "settings.section.display",
        defaultValue: "Display",
        comment: "Settings section header for display preferences"
      ))
    }
  }

  // MARK: - Diagnostics & Analytics section (F-8.02)

  @ViewBuilder
  private var analyticsSection: some View {
    @Bindable var settings = settings
    Section {
      Toggle(isOn: Binding(
        get: { settings.analyticsOptIn },
        set: { newValue in
          if newValue {
            // Toggle-on: set first, then track (SDK lazy-inits on track call).
            settings.analyticsOptIn = true
            analytics.track(
              AnalyticsEvent.analyticsConsentChanged,
              properties: [
                AnalyticsProperty.newValue: true,
                AnalyticsProperty.oldValue: false,
              ]
            )
          } else {
            // Toggle-off ordering per §7.3 analytics-spec.md:
            // 1. Fire consent_changed FIRST while still opted in.
            // 2. Reset the SDK state.
            // 3. Set analyticsOptIn = false so subsequent events are dropped.
            analytics.track(
              AnalyticsEvent.analyticsConsentChanged,
              properties: [
                AnalyticsProperty.newValue: false,
                AnalyticsProperty.oldValue: true,
              ]
            )
            analytics.reset()
            settings.analyticsOptIn = false
          }
        }
      )) {
        Text(String(
          localized: "settings.analytics.toggle.title",
          defaultValue: "Share Anonymous Usage Data",
          comment: "Toggle label for the analytics opt-in in the Diagnostics & Analytics settings section"
        ))
      }
      .tint(.accentColor)
      .accessibilityHint(String(
        localized: "settings.analytics.toggle.accessibilityHint",
        defaultValue: "Allows the app to send anonymous usage data to help improve the app. No expense details, iCloud identifiers, or personal information are ever included.",
        comment: "VoiceOver hint for the analytics opt-in toggle in Settings"
      ))
      .listRowBackground(Color("CellBackground"))
    } header: {
      Text(String(
        localized: "settings.analytics.section.title",
        defaultValue: "Diagnostics & Analytics",
        comment: "Settings section header for the analytics opt-in toggle"
      ))
    } footer: {
      Text(String(
        localized: "settings.analytics.toggle.footer",
        defaultValue: """
        Anonymous usage data helps troubleshoot issues and understand usage. \
        What\u{2019}s included: Budget settings like period, currency code, carry-over on/off, \
        allocation amount, and so on. What\u{2019}s never included: Expense names, amounts, dates, \
        any Apple/iCloud identifiers, any free-text notes or personal information. \
        The initial setting was chosen automatically based on your device\u{2019}s region.
        """,
        comment:
        """
        Footer below the analytics opt-in toggle. Discloses what is/is not transmitted \
        (§5 analytics-spec.md). budget_name and budget_allocation_amount are accepted-risk \
        exceptions. Mentions that the locale-based default can be changed.
        """
      ))
    }
  }
}

// MARK: - SettingsView: iCloud, Support, About, Helpers

private extension SettingsView {
  var iCloudSection: some View {
    Section {
      iCloudStatusRow
        .listRowBackground(Color("CellBackground"))
    } header: {
      Text(String(
        localized: "settings.section.iCloud",
        defaultValue: "iCloud Sync",
        comment: "Settings section header for iCloud sync status"
      ))
    } footer: {
      switch syncStatus.rowState {
      case .unavailable:
        Text(String(
          localized: "settings.iCloud.unavailable.footer",
          defaultValue: "Sign in to iCloud in Settings to sync your budgets across devices.",
          comment: "Section footer shown below the iCloud status row when iCloud is unavailable"
        ))
      case .paused:
        Text(String(
          localized: "settings.iCloud.paused.footer",
          defaultValue:
          "Your budgets are saved on this device only. Restart the app to retry iCloud sync.",
          comment:
          "Section footer shown below the iCloud status row when the app is signed in to iCloud but the SwiftData container is running in local-only mode"
        ))
      default:
        EmptyView()
      }
    }
  }

  var supportSection: some View {
    Section {
      Link(
        String(
          localized: "settings.feedback.label",
          defaultValue: "Send Feedback",
          comment: "Label for the Send Feedback link in Settings"
        ),
        destination: feedbackMailtoURL
      )
      .accessibilityHint(String(
        localized: "settings.feedback.accessibilityHint",
        defaultValue: "Opens a new email to send feedback about the app",
        comment: "VoiceOver hint for the Send Feedback link in Settings"
      ))
      .listRowBackground(Color("CellBackground"))

      Button(String(
        localized: "settings.rateApp.label",
        defaultValue: "Rate the App",
        comment: "Label for the Rate the App button in Settings"
      )) {
        requestReview()
      }
      .accessibilityHint(String(
        localized: "settings.rateApp.accessibilityHint",
        defaultValue: "Opens the App Store rating prompt",
        comment: "VoiceOver hint for the Rate the App button in Settings"
      ))
      .listRowBackground(Color("CellBackground"))

      Link(
        String(
          localized: "settings.privacy.label",
          defaultValue: "Privacy Policy",
          comment: "Label for the Privacy Policy link in Settings"
        ),
        destination: privacyPolicyURL
      )
      .accessibilityHint(String(
        localized: "settings.privacy.accessibilityHint",
        defaultValue: "Opens the privacy policy in your browser",
        comment: "VoiceOver hint for the Privacy Policy link in Settings"
      ))
      .listRowBackground(Color("CellBackground"))
    } header: {
      Text(String(
        localized: "settings.section.support",
        defaultValue: "Support",
        comment: "Settings section header for support and help links"
      ))
    }
  }

  var aboutSection: some View {
    Section {
      HStack {
        Text(String(
          localized: "settings.version.label",
          defaultValue: "Version",
          comment: "Label for the app version row in Settings"
        ))
        Spacer()
        // Locale-invariant numerals + parentheses; use `verbatim:` so the
        // string is not extracted into the catalog and translators never
        // see a `%@ (%@)` format. The accessibilityLabel below carries the
        // real localizable copy ("Version …, build …"). The optional
        // " · Debug" suffix is the only localized piece (extracted via
        // `debugBadge`'s `String(localized:)`); it appears in dev builds only.
        Text(verbatim: "\(appVersion) (\(buildNumber))" + (debugBadge.map { " · \($0)" } ?? ""))
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }
      .accessibilityElement(children: .combine)
      .accessibilityLabel(versionAccessibilityLabel)
      .listRowBackground(Color("CellBackground"))
    }
  }

  // MARK: - iCloud status row

  @ViewBuilder
  var iCloudStatusRow: some View {
    switch syncStatus.rowState {
    case .checking:
      HStack {
        Text(String(
          localized: "settings.iCloud.checking",
          defaultValue: "Checking…",
          comment: "iCloud sync status shown while the account status is being determined"
        ))
        .foregroundStyle(.secondary)
        Spacer()
        ProgressView()
          .accessibilityLabel(String(
            localized: "settings.iCloud.checking.accessibilityLabel",
            defaultValue: "Checking iCloud availability",
            comment: "VoiceOver label for the iCloud status loading indicator"
          ))
      }

    case .available:
      Label {
        Text(String(
          localized: "settings.iCloud.available",
          defaultValue: "iCloud Sync is Active",
          comment: "iCloud sync status label when iCloud is available and active"
        ))
      } icon: {
        Image(systemName: "checkmark.icloud")
          .foregroundStyle(.green)
      }
      .accessibilityLabel(String(
        localized: "settings.iCloud.available.accessibilityLabel",
        defaultValue: "iCloud sync is active",
        comment: "VoiceOver label for the iCloud available status row"
      ))

    case .paused:
      Label {
        Text(String(
          localized: "settings.iCloud.paused",
          defaultValue: "iCloud Sync Paused",
          comment: "iCloud sync status label when the app is signed in to iCloud but the SwiftData container is running in local-only mode"
        ))
      } icon: {
        Image(systemName: "exclamationmark.icloud")
          .foregroundStyle(.orange)
      }
      .accessibilityLabel(String(
        localized: "settings.iCloud.paused.accessibilityLabel",
        defaultValue: "iCloud sync is paused. Your budgets are saved on this device but not syncing to other devices.",
        comment: "VoiceOver label for the iCloud paused status row; shown when signed in but the SwiftData container is local-only"
      ))

    case .unavailable:
      Label {
        Text(String(
          localized: "settings.iCloud.unavailable",
          defaultValue: "iCloud Not Available",
          comment: "iCloud sync status label when iCloud is not signed in or unavailable"
        ))
      } icon: {
        Image(systemName: "xmark.icloud")
          .foregroundStyle(.orange)
      }
      .accessibilityLabel(String(
        localized: "settings.iCloud.unavailable.accessibilityLabel",
        defaultValue: "iCloud not available. Sign in to iCloud in Settings to sync your budgets.",
        comment: "VoiceOver label for the iCloud unavailable status row"
      ))
    }
  }

  // MARK: - Helpers

  func weekdayName(_ weekday: Weekday) -> String {
    Calendar.current.standaloneWeekdaySymbols[weekday.rawValue - 1]
  }

  var feedbackMailtoURL: URL {
    FeedbackMailto.plainURL
  }

  var privacyPolicyURL: URL {
    URL(string: AppInfo.privacyPolicyURL)!
  }

  func loadICloudStatus() async {
    let old = syncStatus.accountStatus
    do {
      let status = try await CKContainer.default().accountStatus()
      syncStatus.accountStatus = status == .available ? .available : .unavailable
    } catch {
      syncStatus.accountStatus = .unavailable
    }
    let new = syncStatus.accountStatus
    if old != new {
      Logger.cloudKit.notice(
        "cloudkit.account.transition: \(String(describing: old), privacy: .public) → \(String(describing: new), privacy: .public)"
      )
    }
  }

  /// Observes iCloud account changes while the sheet is open so the row
  /// updates reactively without requiring a dismiss / re-open.
  ///
  /// Watches both `CKAccountChanged` (CloudKit container sign-in/out) and
  /// `NSUbiquityIdentityDidChange` (iCloud identity token rotation, e.g. account
  /// switch in Settings.app) since each can fire independently.
  func observeAccountChanges() async {
    await withTaskGroup(of: Void.self) { group in
      group.addTask { await observeSingleNotification(.CKAccountChanged) }
      group.addTask { await observeSingleNotification(.NSUbiquityIdentityDidChange) }
    }
  }

  func observeSingleNotification(_ name: NSNotification.Name) async {
    let notifications = NotificationCenter.default.notifications(named: name)
    for await _ in notifications {
      await loadICloudStatus()
    }
  }
}
