import Mixpanel
import SwiftData
import SwiftUI

@main
struct simple_recurring_budgetsApp: App {
  @State private var settings: AppSettings
  @State private var router = Router()
  @State private var syncStatus: SyncStatus
  private let analytics: any AnalyticsClient
  var sharedModelContainer: ModelContainer

  init() {
    #if DEBUG
      let mixpanelToken = "d75149bc04193d5313f130cd688a54c9"
    #else
      let mixpanelToken = "6d8492115467535089006f9ad413cb94"
    #endif
    let client = MixpanelAnalyticsClient(token: mixpanelToken) { false } // TODO: replace with AppSettings opt-in check
    analytics = client
    let (container, backing) = Self.makeModelContainer(analytics: client)
    sharedModelContainer = container
    _settings = State(initialValue: AppSettings())
    _syncStatus = State(initialValue: SyncStatus(containerBacking: backing))
  }

  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(router)
        .environment(settings)
        .environment(syncStatus)
        .environment(\.analytics, analytics)
        .task {
          analytics.track(AnalyticsEvent.appLaunched)
        }
    }
    .modelContainer(sharedModelContainer)
  }

    // MARK: - Private

  // `case normal` is always available. Non-`.normal` cases exist only in DEBUG
  // (see `#if` inside the enum) so they are stripped from Release builds.
  #if DEBUG
    /// -------------------------------------------------------------------------
    /// Manual database launch — set `appDatabaseLaunchMode` below. Options:
    ///
    /// • `.normal` — CloudKit when available, else on-disk (matches App Store behavior).
    /// • `.emptyInMemory` — in-memory, no rows.
    /// • `.emptyPersistedThenClear` — production store, then delete all budgets (**data loss**).
    /// • `.debugDataSeededInMemory` — `DebugData` fixtures, in-memory.
    /// -------------------------------------------------------------------------
    private static let appDatabaseLaunchMode: AppDatabaseLaunchMode = .normal
  #endif

  private enum AppDatabaseLaunchMode: Equatable {
    /// Default: CloudKit-backed `ModelContainer` if possible, else local on-disk. Analytics on outcomes.
    case normal
    #if DEBUG
      /// In-memory, no iCloud, no rows — empty Budgets list.
      case emptyInMemory
      /// Same stack as production, then delete all `Budget`s (cascades expenses). **Wipes local data.**
      case emptyPersistedThenClear
      /// Full `DebugData` fixtures in memory.
      case debugDataSeededInMemory
    #endif
  }

  /// Picks a `ModelContainer` (and the `SyncStatus.ContainerBacking` it represents)
  /// based on `appDatabaseLaunchMode` (DEBUG) or always production (Release).
  ///
  /// In-memory DEBUG containers always use `.localFallback` since they don't sync via CloudKit.
  private static func makeModelContainer(analytics: any AnalyticsClient) -> (ModelContainer, SyncStatus.ContainerBacking) {
    #if DEBUG
      switch appDatabaseLaunchMode {
      case .emptyInMemory:
        return (InMemoryModelContainer.makeEmpty(), .localFallback)
      case .emptyPersistedThenClear:
        let (container, backing) = makeProductionModelContainer(analytics: analytics)
        deleteAllBudgets(in: container.mainContext)
        return (container, backing)
      case .debugDataSeededInMemory:
        return (InMemoryModelContainer.makeSeeded(), .localFallback)
      case .normal:
        return makeProductionModelContainer(analytics: analytics)
      }
    #else
      return makeProductionModelContainer(analytics: analytics)
    #endif
  }

  /// CloudKit if available, else local on disk — the production persistence stack.
  /// Returns the container and the `SyncStatus.ContainerBacking` that reflects
  /// which path was taken (`.cloudKit` or `.localFallback`).
  private static func makeProductionModelContainer(analytics: any AnalyticsClient) -> (ModelContainer, SyncStatus.ContainerBacking) {
    let schema = SchemaV1.swiftDataSchema

    // Try CloudKit-backed storage first. CloudKit requires an active iCloud account;
    // fall back to local-only storage when unavailable (e.g., Simulator without a
    // signed-in account, or offline first launch).
    let cloudConfig = ModelConfiguration(
      schema: schema,
      isStoredInMemoryOnly: false,
      cloudKitDatabase: .automatic
    )
    if let container = try? ModelContainer(
      for: schema,
      migrationPlan: BudgetMigrationPlan.self,
      configurations: cloudConfig
    ) {
      analytics.track(AnalyticsEvent.cloudKitContainerBacked, channel: .cloudKit)
      return (container, .cloudKit)
    }

    analytics.track(AnalyticsEvent.cloudKitContainerLocalFallback, channel: .cloudKit, level: .notice)

    let localConfig = ModelConfiguration(
      schema: schema,
      isStoredInMemoryOnly: false,
      cloudKitDatabase: .none
    )
    do {
      let container = try ModelContainer(
        for: schema,
        migrationPlan: BudgetMigrationPlan.self,
        configurations: localConfig
      )
      analytics.track(AnalyticsEvent.cloudKitContainerLocalSuccess, channel: .cloudKit)
      return (container, .localFallback)
    } catch {
      analytics.track(
        AnalyticsEvent.cloudKitContainerFailed,
        channel: .cloudKit,
        level: .error,
        properties: ["error": error.localizedDescription]
      )
      fatalError("Could not create ModelContainer: \(error)")
    }
  }

  #if DEBUG
    /// Removes every `Budget` (cascade-deletes their `ExpenseItem`s) and saves. For manual
    /// "empty on disk / CloudKit" testing only; see `appDatabaseLaunchMode` `.emptyPersistedThenClear`.
    private static func deleteAllBudgets(in context: ModelContext) {
      let descriptor = FetchDescriptor<Budget>()
      guard let all = try? context.fetch(descriptor) else { return }
      for budget in all {
        context.delete(budget)
      }
      try? context.save()
    }
  #endif
}
