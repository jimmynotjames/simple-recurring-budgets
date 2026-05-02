import Mixpanel
import OSLog

final class MixpanelAnalyticsClient: AnalyticsClient {
  private let isOptedIn: @Sendable () -> Bool

  init(token: String, isOptedIn: @escaping @Sendable () -> Bool) {
    self.isOptedIn = isOptedIn
    Mixpanel.initialize(token: token, trackAutomaticEvents: false)
  }

  func track(_ event: String, channel: AnalyticsChannel, level: AnalyticsLevel, properties: [String: any Sendable]?) {
    switch channel {
    case .bootstrap:
      log(event, to: .bootstrap, level: level, properties: properties)
    case .cloudKit:
      log(event, to: .cloudKit, level: level, properties: properties)
    case .ui:
      log(event, to: .ui, level: level, properties: properties)
    case .product:
      guard isOptedIn() else { return }
      let mixProps = properties?.compactMapValues { $0 as? MixpanelType }
      Mixpanel.mainInstance().track(event: event, properties: mixProps)
    }
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

  // MARK: - Private

  private func log(
    _ event: String,
    to logger: Logger,
    level: AnalyticsLevel,
    properties: [String: any Sendable]?
  ) {
    let message: String = {
      guard let properties, !properties.isEmpty else { return event }
      return "\(event) \(properties.description)"
    }()

    switch level {
    case .info: logger.info("\(message, privacy: .public)")
    case .notice: logger.notice("\(message, privacy: .public)")
    case .error: logger.error("\(message, privacy: .public)")
    }
  }
}
