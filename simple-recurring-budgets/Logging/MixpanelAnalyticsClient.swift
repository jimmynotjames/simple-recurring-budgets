import Mixpanel

final class MixpanelAnalyticsClient: AnalyticsClient {
  private let isOptedIn: @Sendable () -> Bool

  init(token: String, isOptedIn: @escaping @Sendable () -> Bool) {
    self.isOptedIn = isOptedIn
    Mixpanel.initialize(token: token, trackAutomaticEvents: false)
  }

  func track(_ event: String, properties: [String: any Sendable]?) {
    guard isOptedIn() else { return }
    let mixProps = properties?.compactMapValues { $0 as? MixpanelType }
    Mixpanel.mainInstance().track(event: event, properties: mixProps)
  }

  func identify(_ distinctId: String?) {
    guard isOptedIn() else { return }
    if let id = distinctId {
      Mixpanel.mainInstance().identify(distinctId: id)
    }
  }

  func reset() {
    Mixpanel.mainInstance().reset()
  }
}
