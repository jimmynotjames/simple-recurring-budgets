import CloudKit
import StoreKit
import SwiftUI

// MARK: - AppInfo

private enum AppInfo {
  static let feedbackEmail = "jimmyho.appfeedback@gmail.com"
  static let feedbackSubject = "Budgets app feedback"
  // TODO: Replace with real privacy policy URL before launch.
  static let privacyPolicyURL = "https://example.com/privacy"
}

// MARK: - SettingsView

struct SettingsView: View {
  @Environment(AppSettings.self) private var settings
  @Environment(SyncStatus.self) private var syncStatus
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

  var body: some View {
    @Bindable var settings = settings
    NavigationStack {
      Form {
        budgetsSection(carryOverOn: $settings.defaultCarryOverEnabled)
        calendarSection(currentDay: settings.weekStartDay)
        displaySection(currencyDisplay: $settings.currencyDisplay)
        iCloudSection
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
          if let day = pendingWeekStart { settings.weekStartDay = day }
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
        isOn: carryOverOn
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
        selection: currencyDisplay
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

  private var iCloudSection: some View {
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
          defaultValue: "Your budgets are saved on this device only. Restart the app to retry iCloud sync.",
          comment: "Section footer shown below the iCloud status row when the app is signed in to iCloud but the SwiftData container is running in local-only mode"
        ))
      default:
        EmptyView()
      }
    }
  }

  private var supportSection: some View {
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

  private var aboutSection: some View {
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
        // real localizable copy ("Version …, build …").
        Text(verbatim: "\(appVersion) (\(buildNumber))")
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }
      .accessibilityElement(children: .combine)
      .accessibilityLabel(String(
        localized: "settings.version.accessibilityLabel",
        defaultValue: "Version \(appVersion), build \(buildNumber)",
        comment: "VoiceOver label for the app version row; arguments are the version string and build number"
      ))
      .listRowBackground(Color("CellBackground"))
    }
  }

  // MARK: - iCloud status row

  @ViewBuilder
  private var iCloudStatusRow: some View {
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

  private func weekdayName(_ weekday: Weekday) -> String {
    Calendar.current.standaloneWeekdaySymbols[weekday.rawValue - 1]
  }

  private var feedbackMailtoURL: URL {
    let subject = AppInfo.feedbackSubject
      .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
    return URL(string: "mailto:\(AppInfo.feedbackEmail)?subject=\(subject)")!
  }

  private var privacyPolicyURL: URL {
    URL(string: AppInfo.privacyPolicyURL)!
  }

  private func loadICloudStatus() async {
    do {
      let status = try await CKContainer.default().accountStatus()
      syncStatus.accountStatus = status == .available ? .available : .unavailable
    } catch {
      syncStatus.accountStatus = .unavailable
    }
  }

  /// Observes iCloud account changes while the sheet is open so the row
  /// updates reactively without requiring a dismiss / re-open.
  ///
  /// Watches both `CKAccountChanged` (CloudKit container sign-in/out) and
  /// `NSUbiquityIdentityDidChange` (iCloud identity token rotation, e.g. account
  /// switch in Settings.app) since each can fire independently.
  private func observeAccountChanges() async {
    await withTaskGroup(of: Void.self) { group in
      group.addTask { await observeSingleNotification(.CKAccountChanged) }
      group.addTask { await observeSingleNotification(.NSUbiquityIdentityDidChange) }
    }
  }

  private func observeSingleNotification(_ name: NSNotification.Name) async {
    let notifications = NotificationCenter.default.notifications(named: name)
    for await _ in notifications {
      await loadICloudStatus()
    }
  }
}

// MARK: - Preview support

private struct SettingsPreview: View {
  var syncStatus: SyncStatus = .init(containerBacking: .cloudKit, accountStatus: .available)

  var body: some View {
    SettingsView()
      .environment(AppSettings())
      .environment(syncStatus)
  }
}

#Preview("Light Mode") { SettingsPreview() }
#Preview("Dark Mode") { SettingsPreview().preferredColorScheme(.dark) }
#Preview("Accessibility Large") { SettingsPreview().dynamicTypeSize(.accessibility2) }
#Preview("iCloud Unavailable") { SettingsPreview(syncStatus: SyncStatus(containerBacking: .cloudKit, accountStatus: .unavailable)) }
#Preview("iCloud Paused") { SettingsPreview(syncStatus: SyncStatus(containerBacking: .localFallback, accountStatus: .available)) }
