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
  @State private var ratingPrompt: RatingPromptCoordinator
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
    // SyncStatus presents an iCloud indicator in Settings. On the failure
    // path no RootView/SettingsView are constructed, so seed a placeholder
    // `.localFallback`; the ContainerFailureView Retry handler in `body`
    // overwrites it with the real backing once a retry succeeds, so Settings
    // never misreports local-only after recovery.
    let initialSyncStatus = SyncStatus(
      containerBacking: initialStartup.containerBacking ?? .localFallback
    )

    #if DEBUG
      // App Store screenshot capture only: force the Settings iCloud row to read
      // "Active" (the Simulator has no iCloud account, so it would otherwise show
      // "unavailable"). Set solely by the AppStoreScreenshots UI test via this flag;
      // the whole block is compiled out of Release. See SyncStatus.swift.
      if ProcessInfo.processInfo.environment["SCREENSHOT_SYNC_OK"] == "1" {
        initialSyncStatus.screenshotForcesAvailableState = true
      }
    #endif

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
    // F-6.03 rating prompt. Counters live in the iCloud KV store (synced, consent-
    // independent) — same `NSUbiquitousKeyValueStore.default` as AppSettings, in
    // every build including tests. Coordinator-logic tests inject their own
    // in-memory store directly.
    _ratingPrompt = State(initialValue: RatingPromptCoordinator(
      state: RatingPromptState(),
      analytics: analytics
    ))

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
          // `.ratingPromptPresenter()` MUST stay above (inner to) the `.environment`
          // calls below: it reads `Router` / `RatingPromptCoordinator` from the
          // environment, so those must be injected by an outer modifier. Reordering it
          // below the `.environment(...)` lines would crash on launch (missing env).
          .ratingPromptPresenter()
          .modelContainer(container)
          .environment(router)
          .environment(settings)
          .environment(syncStatus)
          .environment(ratingPrompt)
          .environment(\.analytics, analytics)
        // Test-only Dynamic Type override for the localized-layout screenshot check. DEBUG-only, so
        // it's compiled out of Release entirely; even in DEBUG it's inert unless IS_TESTING +
        // FORCE_DYNAMIC_TYPE are set (which only XCUITest does).
        #if DEBUG
          .modifier(TestDynamicTypeOverride())
        #endif
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
          // A successful retry resolved a real backing — correct the
          // placeholder seed so the Settings iCloud row reflects the live
          // container instead of claiming local-only until the next launch
          // (general-code-audit-2026-06-11 L1). No-op on a failed retry
          // (`containerBacking` stays nil and the failure surface persists).
          if let backing = startup.containerBacking {
            syncStatus.containerBacking = backing
          }
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
    // UI test isolation: every test launch gets a clean ephemeral in-memory store.
    // Seeding for journey-test preconditions is handled by InMemoryModelContainer.
    if isRunningTests {
      #if DEBUG
        return (InMemoryModelContainer.makeForUITests(), .localFallback)
      #else
        return (InMemoryModelContainer.makeEmpty(), .localFallback)
      #endif
    }
    #if DEBUG
      switch appDatabaseLaunchMode {
      case .emptyInMemory:
        return (InMemoryModelContainer.makeEmpty(), .localFallback)
      case .emptyPersistedThenClear:
        let (container, backing) = try ProductionContainerFactory.make()
        deleteAllBudgets(in: container.mainContext)
        return (container, backing)
      case .debugDataSeededInMemory:
        return (InMemoryModelContainer.makeSeeded(), .localFallback)
      case .normal:
        return try ProductionContainerFactory.make()
      }
    #else
      return try ProductionContainerFactory.make()
    #endif
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
