import SwiftUI

// MARK: - SettingsView preview support

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
