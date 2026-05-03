import Mixpanel
import OSLog
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
    let mixpanelToken = MixpanelTokenSource.activeToken

    let (container, backing) = Self.makeModelContainer()
    sharedModelContainer = container
    let initialSettings = AppSettings()
    let initialSyncStatus = SyncStatus(containerBacking: backing)

    // Closures are @Sendable and read only Sendable-typed values from the
    // captured references. All call sites in this app are on the main actor,
    // so accessing @Observable main-actor-isolated properties is safe here.
    let client = MixpanelAnalyticsClient(
      token: mixpanelToken,
      isOptedIn: { [initialSettings] in initialSettings.analyticsOptIn },
      distinctIdProvider: { [initialSettings] in initialSettings.analyticsDistinctId },
      weekStartDayProvider: { [initialSettings] in initialSettings.weekStartDay.analyticsValue },
      currencyDisplayProvider: { [initialSettings] in
        initialSettings.currencyDisplay.analyticsValue
      },
      carryOverDefaultProvider: { [initialSettings] in
        initialSettings.defaultCarryOverEnabled
      },
      syncStateProvider: { [initialSyncStatus] in initialSyncStatus.rowState.analyticsValue },
      budgetsCountProvider: { [container] in
        let descriptor = FetchDescriptor<Budget>()
        return (try? container.mainContext.fetchCount(descriptor)) ?? 0
      }
    )
    analytics = client
    _settings = State(initialValue: initialSettings)
    _syncStatus = State(initialValue: initialSyncStatus)
    #if DEBUG
      Logger.bootstrap.info("bootstrap.launchMode: \(String(describing: Self.appDatabaseLaunchMode), privacy: .public)")
    #else
      Logger.bootstrap.info("bootstrap.launchMode: normal")
    #endif
  }

  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(router)
        .environment(settings)
        .environment(syncStatus)
        .environment(\.analytics, analytics)
        .task {
          analytics.track(AnalyticsEvent.appOpened)
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
  private static func makeModelContainer() -> (ModelContainer, SyncStatus.ContainerBacking) {
    #if DEBUG
      switch appDatabaseLaunchMode {
      case .emptyInMemory:
        return (InMemoryModelContainer.makeEmpty(), .localFallback)
      case .emptyPersistedThenClear:
        let (container, backing) = makeProductionModelContainer()
        deleteAllBudgets(in: container.mainContext)
        return (container, backing)
      case .debugDataSeededInMemory:
        return (InMemoryModelContainer.makeSeeded(), .localFallback)
      case .normal:
        return makeProductionModelContainer()
      }
    #else
      return makeProductionModelContainer()
    #endif
  }

  /// CloudKit if available, else local on disk — the production persistence stack.
  /// Returns the container and the `SyncStatus.ContainerBacking` that reflects
  /// which path was taken (`.cloudKit` or `.localFallback`).
  private static func makeProductionModelContainer() -> (ModelContainer, SyncStatus.ContainerBacking) {
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
      Logger.cloudKit.info("cloudkit.container.backed")
      return (container, .cloudKit)
    }

    Logger.cloudKit.notice("cloudkit.container.localFallback")

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
      Logger.cloudKit.info("cloudkit.container.localSuccess")
      return (container, .localFallback)
    } catch {
      Logger.cloudKit.error("cloudkit.container.failed: \(error.localizedDescription, privacy: .public)")
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
