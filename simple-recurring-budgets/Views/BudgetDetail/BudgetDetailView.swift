import OSLog
import SwiftData
import SwiftUI

// MARK: - BudgetDetailView

struct BudgetDetailView: View {
  let budget: Budget

  @Environment(\.modelContext) var context
  @Environment(AppSettings.self) var settings
  @Environment(Router.self) var router
  @Environment(\.analytics) var analytics
  @Environment(\.scenePhase) private var scenePhase

  @State var lifecycle: BudgetLifecycleResult?
  @State private var showResetCarryOverConfirm = false
  @State private var showResetBudgetConfirm = false
  /// Measured height of the content-area large title (issue #117). Drives the
  /// scroll threshold at which the title collapses into the inline nav-bar title.
  /// Varies with name length and Dynamic Type, so it's measured rather than fixed.
  /// Internal (not `private`) so `BudgetDetailView+Title` can write it.
  @State var titleHeight: CGFloat = 0
  /// Whether the inline nav-bar title is shown. Toggles true once the content-area
  /// large title has substantially scrolled beneath the navigation bar. Internal
  /// (not `private`) so `BudgetDetailView+Title` can read it.
  @State var showInlineTitle = false
  /// Standard save-error alert state for interactive actions on this screen
  /// (swipe-delete an expense, Reset Budget, Reset Carry-Over, Pause, Resume).
  /// Populated by `present(_:retry:)` on a `PersistenceError` throw; cleared
  /// by the alert's Cancel / Send Feedback buttons or a successful retry.
  @State var saveError: SaveErrorState?

  /// Action-gating only: the primary slot swaps Add Expense → Resume Budget
  /// while paused, per the existing budget-detail-screen primary-action
  /// requirement. Presentation (header dimming, chip) reads `inactiveReason`
  /// below, not this flag.
  private var isPaused: Bool {
    lifecycle?.lifecycleState == .paused
  }

  /// Action-gating only: hides the Pause/Resume menu item past `endDate` per
  /// F-7.07 (a terminal budget cannot be paused or resumed).
  private var isPostEnd: Bool {
    lifecycle?.lifecycleState == .postEnd
  }

  /// View-layer inactive-presentation reason (`nil` when the budget is active).
  /// Drives the dimmed header amount / full-width secondary bar /
  /// `InactiveStatusChip` treatment uniformly across preStart, paused, and postEnd.
  private var inactiveReason: BudgetInactiveReason? {
    guard let lifecycle else { return nil }
    return BudgetInactiveReason.from(lifecycle: lifecycle, budget: budget)
  }

  private var isSpecificDates: Bool {
    budget.periodEnum == .specificDates
  }

  private var showPauseResumeItem: Bool {
    !isSpecificDates && !isPostEnd
  }

  @ScaledMetric(relativeTo: .caption) private var chipTopSpacing: CGFloat = 16
  @ScaledMetric(relativeTo: .body) private var rowVerticalPadding: CGFloat = 8

  var period: BudgetPeriod {
    budget.periodEnum
  }

  private var remaining: Decimal {
    lifecycle?.remaining ?? 0
  }

  private var carryOverAmount: Decimal {
    lifecycle?.carryOverAmount ?? 0
  }

  var body: some View {
    List {
      // ── Content-area large title ──────────────────────────────
      // Scroll-aware title (issue #117): renders the icon as a leading view so it
      // mirrors in RTL, wraps long names, and collapses into the inline nav-bar
      // title on scroll — none of which `navigationTitle(String)` can do.
      Section {
        titleHeader
          .listRowBackground(Color.clear)
          .listRowSeparator(.hidden)
          // Leading/trailing 0: align the title with the cards' outer edge (where
          // the status-quo large title sat), not the text inside them. Inset-grouped
          // row insets are measured from the card edge, so 0 = flush with the card.
          .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
      }
      // Tighten the gap below the title to roughly the old large-title→content
      // spacing; without this the title gets the full inset-grouped section gap.
      .listSectionSpacing(8)

      // ── Status header ─────────────────────────────────────────
      Section {
        headerRow
          .listRowBackground(Color("CellBackground"))
          .listRowSeparator(.hidden)
      }

      // ── Primary action ────────────────────────────────────────
      Section {
        VStack(spacing: 8) {
          if isPaused {
            Button {
              resumeBudgetTapped()
            } label: {
              HStack(spacing: 8) {
                Image(systemName: "play.circle")
                Text(String(
                  localized: "budgetDetail.action.resume",
                  defaultValue: "Resume Budget",
                  comment: "Label on the primary action button when the budget is paused"
                ))
              }
              .font(.headline)
              .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.accentFill)
            .controlSize(.large)
            .accessibilityLabel(String(
              localized: "budgetDetail.action.resume.accessibilityLabel",
              defaultValue: "Resume \(budget.name)",
              comment: "VoiceOver label for the resume budget button; argument is the budget name"
            ))
            .accessibilityHint(String(
              localized: "budgetDetail.action.resume.accessibilityHint",
              defaultValue: "Resumes the budget so you can log expenses again",
              comment: "VoiceOver hint for the resume budget button"
            ))
            if let pausedSince = lifecycle?.pausedSince {
              Text(String(
                localized: "budgetDetail.action.resume.caption.format",
                defaultValue: "Paused since \(pausedSince.formatted(date: .abbreviated, time: .omitted)). Resume to log new expenses.",
                comment: "Caption below the Resume Budget button; argument is the abbreviated pause date"
              ))
              .font(.caption)
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity, alignment: .center)
            }
          } else {
            Button {
              router.sheet = .addExpense(budget.id)
            } label: {
              HStack(spacing: 8) {
                Image(systemName: "plus")
                Text(String(
                  localized: "budgetDetail.action.addExpense",
                  defaultValue: "Add Expense",
                  comment: "Label on the primary action button that opens the add expense form"
                ))
              }
              .font(.headline)
              .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.accentFill)
            .controlSize(.large)
            .accessibilityLabel(String(
              localized: "budgetDetail.action.addExpense.accessibilityLabel",
              defaultValue: "Add expense to \(budget.name)",
              comment: "VoiceOver label for the add expense button; argument is the budget name"
            ))
            .accessibilityHint(String(
              localized: "budgetDetail.action.addExpense.accessibilityHint",
              defaultValue: "Opens the add expense form",
              comment: "VoiceOver hint for the add expense button"
            ))
          }
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
      }

      // ── Expense list ──────────────────────────────────────────
      expenseSection
    }
    .listStyle(.insetGrouped)
    .scrollContentBackground(.hidden)
    // Drop the inset-grouped list's default top inset so the title sits just below
    // the nav bar (its own 8pt row inset is the only remaining gap), instead of the
    // large grouped top margin (issue #117 follow-up).
    .contentMargins(.top, 0, for: .scrollContent)
    // The budget title is rendered as a scroll-aware content header (issue #117),
    // not a string `navigationTitle`. Inline display mode frees the nav-bar center
    // for the custom collapsed title (the `.principal` toolbar item below).
    .navigationBarTitleDisplayMode(.inline)
    // Collapse the content title into the inline nav-bar title once it has
    // substantially (~60%) scrolled beneath the bar. At rest the expression is 0
    // (and `titleHeight` is 0 before first measurement), so the inline title stays
    // hidden until the user scrolls down.
    .onScrollGeometryChange(for: Bool.self) { geometry in
      geometry.contentOffset.y + geometry.contentInsets.top > titleHeight * 0.6
    } action: { _, collapsed in
      withAnimation(.easeInOut(duration: 0.2)) {
        showInlineTitle = collapsed
      }
    }
    .appBackground()
    .saveErrorAlert($saveError)
    .toolbar {
      // Custom inline title (issue #117): fades in as the content-area large title
      // scrolls under the bar. Renders the icon as a leading view (RTL-correct) and
      // truncates to one line, matching the standard inline nav-title weight.
      ToolbarItem(placement: .principal) {
        inlineTitle
      }
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          Button(
            String(
              localized: "budgetDetail.menu.editBudget",
              defaultValue: "Edit Budget",
              comment: "Menu item that opens the edit budget form"
            ),
            systemImage: "pencil"
          ) {
            router.sheet = .editBudget(budget.id)
          }
          if showPauseResumeItem {
            if isPaused {
              Button(
                String(
                  localized: "budgetDetail.menu.resumeBudget",
                  defaultValue: "Resume Budget",
                  comment: "Menu item to resume a paused budget"
                ),
                systemImage: "play.circle"
              ) {
                resumeBudgetTapped()
              }
            } else {
              Button(
                String(
                  localized: "budgetDetail.menu.pauseBudget",
                  defaultValue: "Pause Budget",
                  comment: "Menu item to pause an active budget"
                ),
                systemImage: "pause.circle"
              ) {
                pauseBudgetTapped()
              }
            }
          }
          Divider()
          if budget.isCarryOverEnabled, !isSpecificDates {
            Button(
              String(
                localized: "budgetDetail.menu.resetCarryOver",
                defaultValue: "Reset Carry-Over…",
                comment: "Menu item that opens the reset carry-over confirmation alert; mirrors the 'Reset Budget…' menu item naming convention"
              ),
              systemImage: "arrow.counterclockwise.circle",
              role: .destructive
            ) {
              showResetCarryOverConfirm = true
            }
            .accessibilityHint(String(
              localized: "budgetDetail.menu.resetCarryOver.accessibilityHint",
              defaultValue: "Clears the carry-over balance to zero. Expenses are not affected.",
              comment: "VoiceOver hint for the Reset Carry-Over menu item, communicating the destructive (but non-cascading) consequence"
            ))
          }
          Button(
            String(
              localized: "budgetDetail.menu.resetBudget",
              defaultValue: "Reset Budget…",
              comment: "Menu item that opens the reset budget confirmation dialog"
            ),
            systemImage: "arrow.counterclockwise",
            role: .destructive
          ) {
            showResetBudgetConfirm = true
          }
          .accessibilityHint(String(
            localized: "budgetDetail.menu.resetBudget.accessibilityHint",
            defaultValue: "Permanently deletes every expense for this budget, resets carry-over to zero, and resumes the budget if it is paused.",
            comment: "VoiceOver hint for the destructive Reset Budget menu item, communicating the irreversible consequence"
          ))
        } label: {
          Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel(String(
          localized: "budgetDetail.menu.accessibilityLabel",
          defaultValue: "Budget options",
          comment: "VoiceOver label for the budget options menu button"
        ))
        // Locale-invariant test handle (= localization key) so UI tests navigate in any language.
        // Sole consumer: LocalizationScreenshotCapture (scripts/translation-accessibility-size-check/).
        // Don't remove/rename without updating that capture, or its navigation breaks silently.
        .accessibilityIdentifier("budgetDetail.menu.accessibilityLabel")
        .confirmationDialog(
          String(
            localized: "budgetDetail.resetBudget.dialog.title",
            defaultValue: "Reset Budget?",
            comment: "Title of the confirmation dialog when the user chooses to reset a budget"
          ),
          isPresented: $showResetBudgetConfirm,
          titleVisibility: .visible
        ) {
          Button(
            String(
              localized: "budgetDetail.resetBudget.dialog.confirm",
              defaultValue: "Reset Budget",
              comment: "Destructive confirm button in the reset budget confirmation dialog"
            ),
            role: .destructive
          ) { resetBudget() }
        } message: {
          Text(String(
            localized: "budgetDetail.resetBudget.dialog.message",
            defaultValue: "All expenses will be permanently deleted, carry-over will reset to zero, and if paused, the budget will resume.",
            comment: "Body of the reset-budget confirmation dialog."
          ))
        }
      }
    }
    .alert(
      String(
        localized: "budgetDetail.resetCarryOver.alert.title",
        defaultValue: "Reset carry-over?",
        comment: "Title of the alert when the user resets the carry-over balance to zero"
      ),
      isPresented: $showResetCarryOverConfirm
    ) {
      Button(
        String(
          localized: "budgetDetail.resetCarryOver.alert.confirm",
          defaultValue: "Reset to Zero",
          comment: "Destructive confirm button in the reset carry-over alert"
        ),
        role: .destructive
      ) { resetCarryOver() }
    } message: {
      Text(String(
        localized: "budgetDetail.resetCarryOver.alert.message",
        defaultValue: "The carry-over balance will be cleared and start fresh from zero.",
        comment: "Body of the reset carry-over alert"
      ))
    }
    .task(id: budget.persistentModelID) {
      refreshLifecycle()
    }
    .onChange(of: scenePhase) { _, newPhase in
      guard newPhase == .active else { return }
      refreshLifecycle()
    }
    // Recompute when the budget OR any of its children change — including a CloudKit
    // remote merge that brings in expenses without re-bumping `budget.lastModified`
    // (issue #127). See `Budget.recomputeToken`.
    .onChange(of: budget.recomputeToken) {
      refreshLifecycle()
    }
    // Recompute when a period boundary passes while the app stays foregrounded
    // (issue #70) — scenePhase/recomputeToken don't fire at midnight.
    .onCalendarDayChange {
      refreshLifecycle()
    }
  }

  // MARK: - Header row

  private var headerRow: some View {
    VStack(alignment: .leading, spacing: 0) {
      BudgetRemainingSummary(
        remaining: remaining,
        allocation: budget.currentAllocation,
        periodDisplayLabel: budget.periodDisplayLabel,
        currencyCode: budget.currencyCode,
        currencyDisplay: settings.currencyDisplay,
        inactiveReason: inactiveReason
      )
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(BudgetRemainingSummary.accessibilityLabel(
        budgetName: nil,
        remaining: remaining,
        allocation: budget.currentAllocation,
        isSpecificDates: isSpecificDates,
        periodInlineLabel: budget.periodInlineLabel,
        currencyCode: budget.currencyCode,
        currencyDisplay: settings.currencyDisplay,
        inactiveReason: inactiveReason
      ))
      .accessibilityAddTraits(.isHeader)

      StatusChipRow(
        inactiveReason: inactiveReason,
        isCarryOverEnabled: budget.isCarryOverEnabled && !isSpecificDates,
        carryOverAmount: carryOverAmount,
        currencyCode: budget.currencyCode,
        currencyDisplay: settings.currencyDisplay,
        topSpacing: chipTopSpacing
      )
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, rowVerticalPadding)
  }

  // MARK: - Actions

  func refreshLifecycle() {
    lifecycle = BudgetLifecycleService.result(for: budget)
  }

  // pauseBudgetTapped / resumeBudgetTapped live in BudgetDetailView+PauseResume.swift

  func resetCarryOver() {
    Logger.ui.debug(
      "ui.action: resetCarryOver budget=\(String(describing: budget.persistentModelID), privacy: .private)"
    )
    let period = budget.periodEnum
    do {
      try BudgetLifecycleService.resetCarryOver(budget, context: context, analytics: analytics)
    } catch let error as PersistenceError {
      // Failed save: populate save-error state and skip the analytics event.
      saveError.setForFailure(error, retry: { [self] in resetCarryOver() })
      return
    } catch {
      // Helper only throws PersistenceError, but keep an exhaustive catch for safety.
      return
    }
    saveError.clear()
    // ⚠️ Boundary-adjacent (sibling pattern): Logger.ui.debug above (F-8.01) and
    // analytics.track below (F-8.02) are independent siblings. See design.md D6.
    // The analytics event fires only on a successful save (budget-lifecycle delta spec).
    analytics.track(
      AnalyticsEvent.carryOverReset,
      properties: [
        AnalyticsProperty.period: period.analyticsValue,
        AnalyticsProperty.carryOverEnabled: budget.isCarryOverEnabled,
        AnalyticsProperty.currencyCode: budget.currencyCode,
        AnalyticsProperty.budgetName: budget.name,
        AnalyticsProperty.budgetAllocationAmount: (budget.currentAllocation as NSDecimalNumber).doubleValue,
      ]
    )
    refreshLifecycle()
  }

  func resetBudget() {
    Logger.ui.debug(
      "ui.action: resetBudget budget=\(String(describing: budget.persistentModelID), privacy: .private)"
    )
    let period = budget.periodEnum
    do {
      try withAnimation {
        try BudgetLifecycleService.resetBudget(budget, context: context, analytics: analytics)
      }
    } catch let error as PersistenceError {
      saveError.setForFailure(error, retry: { [self] in resetBudget() })
      return
    } catch {
      return
    }
    saveError.clear()
    // ⚠️ Boundary-adjacent (sibling pattern): Logger.ui.debug above (F-8.01) and
    // analytics.track below (F-8.02) are independent siblings. See design.md D6.
    // The analytics event fires only on a successful save (budget-lifecycle delta spec).
    analytics.track(
      AnalyticsEvent.budgetReset,
      properties: [
        AnalyticsProperty.period: period.analyticsValue,
        AnalyticsProperty.carryOverEnabled: budget.isCarryOverEnabled,
        AnalyticsProperty.currencyCode: budget.currencyCode,
        AnalyticsProperty.budgetName: budget.name,
        AnalyticsProperty.budgetAllocationAmount: (budget.currentAllocation as NSDecimalNumber).doubleValue,
      ]
    )
    refreshLifecycle()
  }
}

// MARK: - Preview

#if DEBUG
  private struct BudgetDetailPreview: View {
    let budget: Budget
    let container: ModelContainer

    init(budget: Budget, icon: String? = nil, name: String? = nil) {
      if let icon { budget.icon = icon }
      if let name { budget.name = name }
      self.budget = budget
      let container = InMemoryModelContainer.makeEmpty()
      DebugData.insertDetail(budget, into: container.mainContext)
      self.container = container
    }

    var body: some View {
      NavigationStack {
        BudgetDetailView(budget: budget)
      }
      .modelContainer(container)
      .environment(Router())
      .environment(AppSettings())
    }
  }

  // Current-period expenses only (daily budget, all from today). With icon.
  #Preview("Current Period Only") {
    BudgetDetailPreview(budget: DebugData.detailDailyCurrentOnly(), icon: "🍔")
  }

  // Both current and past period expenses (monthly, long — exceeds screen height). With icon.
  #Preview("Current & Past Months") {
    BudgetDetailPreview(budget: DebugData.detailMonthlyCurrentAndPast(), icon: "🛍️")
  }

  // Future-dated expenses — "Upcoming" bucket above the current section;
  // current and past sections render below (audit L2). With icon.
  #Preview("Upcoming · Daily") {
    BudgetDetailPreview(budget: DebugData.detailDailyWithUpcoming(), icon: "🍔")
  }

  // No current-period expenses; all expenses are from past periods (weekly budget).
  #Preview("Past Periods Only") {
    BudgetDetailPreview(budget: DebugData.detailWeeklyPastOnly())
  }

  // Empty — no expenses at all.
  #Preview("Empty") {
    BudgetDetailPreview(budget: DebugData.detailWeeklyEmpty())
  }

  // Carry-over disabled. With icon.
  #Preview("Carry-Over Disabled") {
    BudgetDetailPreview(budget: DebugData.detailMonthlyCarryOverDisabled(), icon: "🏠")
  }

  // Dark mode, over budget.
  #Preview("Dark · Over Budget") {
    BudgetDetailPreview(budget: DebugData.detailWeeklyOverBudget())
      .preferredColorScheme(.dark)
  }

  // Paused budget — primary slot shows Resume, header greyed. With icon.
  #Preview("Paused") {
    BudgetDetailPreview(budget: DebugData.detailDailyPaused(), icon: "☕")
  }

  // Specific Dates — date range in header, no carry-over chip. With icon.
  #Preview("Specific Dates · Light") {
    BudgetDetailPreview(budget: DebugData.detailSpecificDates(), icon: "✈️")
  }

  #Preview("Specific Dates · Dark") {
    BudgetDetailPreview(budget: DebugData.detailSpecificDates())
      .preferredColorScheme(.dark)
  }

  // Pre-start: budget hasn't started yet — allocation shown, full-width grey bar,
  // "Starts {date}" chip.
  #Preview("Pre-start · Daily") {
    BudgetDetailPreview(budget: DebugData.detailDailyPreStart())
  }

  // Post-end: budget's endDate has passed — allocation shown, full-width grey bar,
  // "Ended {date}" chip. With icon.
  #Preview("Post-end · Monthly") {
    BudgetDetailPreview(budget: DebugData.detailMonthlyPostEnd(), icon: "🎁")
  }

  // Specific Dates pre-window: same inactive treatment, no carry-over chip.
  #Preview("Specific Dates · Pre-window") {
    BudgetDetailPreview(budget: DebugData.detailSpecificDatesPreStart())
  }

  // Specific Dates post-window: same inactive treatment, no carry-over chip. With icon.
  #Preview("Specific Dates · Post-window") {
    BudgetDetailPreview(budget: DebugData.detailSpecificDatesPostEnd(), icon: "🏝️")
  }

  // Long name — content-area title wraps to multiple lines instead of truncating (issue #117).
  #Preview("Long Name · Wrapping") {
    BudgetDetailPreview(
      budget: DebugData.detailDailyCurrentOnly(),
      icon: "🛒",
      name: "Weekend Groceries, Household Supplies & Sundry Bits"
    )
  }

  // RTL — icon sits on the leading (right) edge, mirroring the list row (issue #117).
  #Preview("Long Name · RTL") {
    BudgetDetailPreview(
      budget: DebugData.detailDailyCurrentOnly(),
      icon: "🛒",
      name: "ميزانية البقالة ومستلزمات المنزل لعطلة نهاية الأسبوع"
    )
    .environment(\.layoutDirection, .rightToLeft)
  }
#endif
