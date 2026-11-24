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

  @Environment(\.scenePhase) private var scenePhase
  /// Fires `app_opened` on cold launch and on each foreground return from background, ignoring transient `.inactive`.
  @State private var appOpenTracker = AppOpenTracker()

  init() {
    // On failure the body shows ContainerFailureView (Retry / Send Feedback) instead of crashing.
    let initialStartup = AppStartup {
      try Self.makeModelContainer()
    }
    _startup = State(initialValue: initialStartup)

    let initialSettings = AppSettings()
    // Settings shows an iCloud indicator via SyncStatus. On the failure path no RootView/SettingsView exists,
    // so seed a placeholder `.localFallback`; the Retry handler in `body` overwrites it with the real backing
    // after a successful retry.
    let initialSyncStatus = SyncStatus(
      containerBacking: initialStartup.containerBacking ?? .localFallback
    )

    #if DEBUG
      // Screenshot capture only: force the Settings iCloud row to "Active" (the Simulator has no iCloud
      // account). Set by the AppStoreScreenshots UI test; compiled out of Release. See SyncStatus.swift.
      if ProcessInfo.processInfo.environment["SCREENSHOT_SYNC_OK"] == "1" {
        initialSyncStatus.screenshotForcesAvailableState = true
      }
    #endif

    // Use ConsoleAnalyticsClient (log-only) when:
    //   • running under any test (IS_TESTING=1), so test events never reach Mixpanel. Applies only to this
    //     @main constructor; other call sites inject SpyAnalyticsClient directly.
    //   • Mixpanel tokens are still the committed placeholders (fresh clone without
    //     config/Secrets.local.xcconfig): no SDK init, no network.
    if Self.isRunningTests || !MixpanelTokenSource.isConfigured {
      analytics = ConsoleAnalyticsClient()
    } else {
      // Closures capture @MainActor-isolated state (AppSettings, SyncStatus, ModelContainer.mainContext) and are
      // deliberately not @Sendable: thread safety rests on MixpanelAnalyticsClient's @unchecked Sendable, which
      // holds because all call sites (track, identify) run on the main actor.
      analytics = MixpanelAnalyticsClient(
        token: MixpanelTokenSource.activeToken,
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
        // Reads through `AppStartup`: zero on the failure path (no container), else the live container.
        budgetsCountProvider: { [initialStartup] in
          guard let container = initialStartup.container else { return 0 }
          let descriptor = FetchDescriptor<Budget>()
          return (try? container.mainContext.fetchCount(descriptor)) ?? 0
        }
      )
    }
    // Rating prompt (F-6.03). Counters live in the iCloud KV store (synced, consent-independent), the same
    // `NSUbiquitousKeyValueStore.default` as AppSettings, in every build including tests. Coordinator tests
    // inject their own in-memory store.
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
          // `.ratingPromptPresenter()` MUST stay above (inner to) the `.environment` calls below: it reads `Router` /
          // `RatingPromptCoordinator` from the environment, which an outer modifier must inject. Moving it below
          // them crashes on launch (missing env).
          .ratingPromptPresenter()
          .modelContainer(container)
          .environment(router)
          .environment(settings)
          .environment(syncStatus)
          .environment(ratingPrompt)
          .environment(\.analytics, analytics)
        // Test-only Dynamic Type override (localized-layout screenshot check). DEBUG-only; inert unless IS_TESTING + FORCE_DYNAMIC_TYPE are set.
        #if DEBUG
          .modifier(TestDynamicTypeOverride())
        #endif
          .task {
            // Cold-launch open; the tracker dedups against the scenePhase handler below so launch never double-fires.
            if appOpenTracker.shouldFire(for: .active) {
              analytics.track(AnalyticsEvent.appOpened)
            }
          }
          .onChange(of: scenePhase) { _, newPhase in
            // Foreground return counts as a new open; transient .inactive does not (the tracker handles it).
            if appOpenTracker.shouldFire(for: newPhase) {
              analytics.track(AnalyticsEvent.appOpened)
            }
          }
      } else if let error = startup.error {
        // Recovery surface. Deliberately gets no Router / AppSettings / SyncStatus / analytics: a wedged store may
        // make them unsafe, and the failure view doesn't need them.
        ContainerFailureView(error: error) {
          startup.retry()
          // A successful retry resolved a real backing: correct the placeholder seed so Settings reflects it instead
          // of claiming local-only until next launch. No-op on a failed retry (`containerBacking` stays nil).
          if let backing = startup.containerBacking {
            syncStatus.containerBacking = backing
          }
        }
      }
    }
  }

  // MARK: - Private

  /// `true` when the process should suppress real analytics. `IS_TESTING = 1` is the single signal for both test types:
  /// - **Unit tests**: set in the scheme's TestAction `EnvironmentVariables` (visible to the app-as-test-host).
  /// - **UI tests**: set via `launchEnvironment["IS_TESTING"] = "1"` at each `XCUIApplication` call site.
  private static var isRunningTests: Bool {
    ProcessInfo.processInfo.environment["IS_TESTING"] != nil
  }

  // `.normal` always exists; other cases are DEBUG-only (`#if` inside the enum) so Release strips them.
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

  /// Picks a `ModelContainer` and its `SyncStatus.ContainerBacking` from `appDatabaseLaunchMode` (DEBUG) or
  /// always production (Release). In-memory DEBUG containers use `.localFallback` (no CloudKit).
  private static func makeModelContainer() throws -> (ModelContainer, SyncStatus.ContainerBacking) {
    // UI test isolation: every launch gets a clean in-memory store; journey preconditions are seeded by InMemoryModelContainer.
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
    /// Removes every `Budget` (cascades to `ExpenseItem`s) and saves. Manual "empty on disk / CloudKit" testing
    /// only (`.emptyPersistedThenClear`).
    private static func deleteAllBudgets(in context: ModelContext) {
      let descriptor = FetchDescriptor<Budget>()
      guard let all = try? context.fetch(descriptor) else { return }
      for budget in all {
        context.delete(budget)
      }
      // DEBUG-only: route through the shared helper so failures still log to Logger.persistence.error; swallowed since this dev-only flow has no analytics or UI.
      try? context.saveChanges(operation: .appLaunchDedup)
    }
  #endif
}
