import Mixpanel
import OSLog
import SwiftData
import SwiftUI

@main
struct simple_recurring_budgetsApp: App {
  @State private var settings: AppSettings
  @State private var router = Router()
  @State private var syncStatus: SyncStatus
  @State private var startup: AppStartup
  private let analytics: any AnalyticsClient

  init() {
    let mixpanelToken = MixpanelTokenSource.activeToken

    // Attempt container creation via AppStartup. On failure, the app body
    // presents ContainerFailureView (Retry / Send Feedback) instead of
    // crashing — see `container-creation-recovery` capability.
    let initialStartup = AppStartup {
      try Self.makeModelContainer()
    }
    _startup = State(initialValue: initialStartup)

    let initialSettings = AppSettings()
    // SyncStatus presents an iCloud indicator in Settings; on the failure
    // path, no RootView/SettingsView are constructed, so the seed value
    // doesn't matter. Default to `.localFallback` when no backing exists.
    let initialSyncStatus = SyncStatus(
      containerBacking: initialStartup.containerBacking ?? .localFallback
    )

    // Narrow test-host escape hatch: when the app runs under any test type
    // (IS_TESTING=1 in the environment), the full @main App still launches
    // and `.task { analytics.track(.appOpened) }` fires. Substituting
    // ConsoleAnalyticsClient prevents those events from reaching Mixpanel.
    // This guard applies only to this @main constructor — all other call
    // sites use @Environment(\.analytics) injection with SpyAnalyticsClient.
    if Self.isRunningTests {
      analytics = ConsoleAnalyticsClient()
    } else {
      // Closures capture @MainActor-isolated properties (AppSettings, SyncStatus,
      // ModelContainer.mainContext). They are NOT @Sendable — thread safety is
      // delegated to the @unchecked Sendable declaration on MixpanelAnalyticsClient,
      // which is safe because all call sites (track, identify) run on the main actor.
      analytics = MixpanelAnalyticsClient(
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
        // Reads through `AppStartup`: on the failure path no container exists,
        // so the count is zero. On the success path (the common case), the
        // live container resolved at launch is captured here.
        budgetsCountProvider: { [initialStartup] in
          guard let container = initialStartup.container else { return 0 }
          let descriptor = FetchDescriptor<Budget>()
          return (try? container.mainContext.fetchCount(descriptor)) ?? 0
        }
      )
    }
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
      if let container = startup.container {
        RootView()
          .modelContainer(container)
          .environment(router)
          .environment(settings)
          .environment(syncStatus)
          .environment(\.analytics, analytics)
          .task {
            analytics.track(AnalyticsEvent.appOpened)
          }
      } else if let error = startup.error {
        // Recovery surface — see `container-creation-recovery` capability.
        // Intentionally does NOT receive Router / AppSettings / SyncStatus /
        // analytics: the wedged-store state may make those unsafe to use,
        // and the failure view does not need them.
        ContainerFailureView(error: error) {
          startup.retry()
        }
      }
    }
  }

  // MARK: - Private

  /// `true` when the process should suppress real analytics.
  ///
  /// `IS_TESTING = 1` is the single canonical signal for both test types:
  /// - **Unit tests**: set via the scheme's TestAction `EnvironmentVariables`,
  ///   which are visible to the app-as-test-host process at launch.
  /// - **UI tests**: injected by each `XCUIApplication` call site via
  ///   `launchEnvironment["IS_TESTING"] = "1"` before `launch()`.
  private static var isRunningTests: Bool {
    ProcessInfo.processInfo.environment["IS_TESTING"] != nil
  }

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
  private static func makeModelContainer() throws -> (ModelContainer, SyncStatus.ContainerBacking) {
    // UI test isolation: use an ephemeral in-memory store so every test launch
    // starts with a clean, empty database. Data created in one test cannot bleed
    // into subsequent tests, removing the need for explicit teardown.
    if isRunningTests {
      let container = InMemoryModelContainer.makeEmpty()
      // SEED_BUDGETS: comma-separated budget names injected via launchEnvironment
      // by makeApp(seedBudgets:) in UITestHelpers. Creates one monthly $100 budget
      // per name so journey tests can skip UI creation and test the feature itself.
      if let seedList = ProcessInfo.processInfo.environment["SEED_BUDGETS"] {
        let now = Date()
        let startDate = Calendar.current.startOfDay(for: now)
        for name in seedList.split(separator: ",").map(String.init).filter({ !$0.isEmpty }) {
          let budget = Budget(name: name, period: .monthly)
          budget.startDate = startDate
          budget.sortOrder = (try? Budget.nextSortOrder(for: container.mainContext)) ?? 0
          let change = AllocationChange(effectiveFrom: startDate, amount: 100)
          change.budget = budget
          budget.allocationChangesStorage = [change]
          container.mainContext.insert(budget)
          container.mainContext.insert(change)
        }
        try? container.mainContext.save()
      }
      return (container, .localFallback)
    }
    #if DEBUG
      switch appDatabaseLaunchMode {
      case .emptyInMemory:
        return (InMemoryModelContainer.makeEmpty(), .localFallback)
      case .emptyPersistedThenClear:
        let (container, backing) = try makeProductionModelContainer()
        deleteAllBudgets(in: container.mainContext)
        return (container, backing)
      case .debugDataSeededInMemory:
        return (InMemoryModelContainer.makeSeeded(), .localFallback)
      case .normal:
        return try makeProductionModelContainer()
      }
    #else
      return try makeProductionModelContainer()
    #endif
  }

  /// CloudKit if available, else local on disk — the production persistence stack.
  /// Returns the container and the `SyncStatus.ContainerBacking` that reflects
  /// which path was taken (`.cloudKit` or `.localFallback`).
  static func makeProductionModelContainer() throws -> (ModelContainer, SyncStatus.ContainerBacking) {
    let schema = SchemaV1.swiftDataSchema

    // Anchor both the CloudKit-enabled and local-only configurations to a single
    // explicit on-disk store URL. Without this, the two configurations rely on
    // SwiftData's *implicit* default store path; if those paths ever diverged
    // (the "split-brain" risk in issue #1), an offline first launch would write
    // to one file and a later online launch would open a different, empty file,
    // making the user's first-session data appear to vanish. Asking SwiftData
    // for the default configuration's own `url` (rather than hardcoding a path)
    // guarantees we pin to the exact location existing installs already use, so
    // both configurations resolve to the same file across launches — only the
    // CloudKit mirroring differs.
    let storeURL = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false).url

    // Try CloudKit-backed storage first. CloudKit requires an active iCloud account;
    // fall back to local-only storage when unavailable (e.g., Simulator without a
    // signed-in account, or offline first launch). Both paths share `storeURL`, so
    // the local-only store is promoted to CloudKit-backed in place once iCloud
    // becomes available — no data is stranded in a forked store.
    let cloudConfig = ModelConfiguration(
      schema: schema,
      url: storeURL,
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
      url: storeURL,
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
      // Both creation paths failed. Log the diagnostic per the
      // `diagnostic-logging` capability, then surface the error to
      // `AppStartup` instead of crashing — `ContainerFailureView` presents
      // Retry + Send Feedback. See `container-creation-recovery` spec.
      Logger.cloudKit.error("cloudkit.container.failed: \(error.localizedDescription, privacy: .public)")
      throw error
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
      // DEBUG-only emptyPersistedThenClear path: route through the shared helper
      // so a failure still logs to Logger.persistence.error; swallow because
      // there is no analytics client or presenting UI in this dev-only flow.
      try? context.saveChanges(operation: .appLaunchDedup)
    }
  #endif
}
