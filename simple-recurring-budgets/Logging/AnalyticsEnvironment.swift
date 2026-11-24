import SwiftUI

extension EnvironmentValues {
  /// The active analytics client. Inject a `SpyAnalyticsClient` in tests or Previews to capture events without real log output.
  @Entry var analytics: any AnalyticsClient = ConsoleAnalyticsClient()
}
