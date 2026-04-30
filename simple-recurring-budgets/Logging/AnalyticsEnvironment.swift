import SwiftUI

extension EnvironmentValues {
  /// The active analytics client for the current environment.
  ///
  /// Inject a `SpyAnalyticsClient` in tests or SwiftUI Previews to capture
  /// events without producing real log output.
  @Entry var analytics: any AnalyticsClient = ConsoleAnalyticsClient()
}
