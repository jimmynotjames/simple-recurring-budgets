import SwiftData
import SwiftUI

struct AddEditBudgetView: View {
  // MARK: - View state

  //
  // Internal: cross-file extension access only.
  //
  // `viewModel`, `settings`, `showCurrencyPicker`, `initialCurrencyCode`,
  // `isScheduleExpanded`, `isNameFocused`, and the `sectionLabel` helper below are
  // non-`private` solely because Swift extensions in `AddEditBudgetView+AllocationCard.swift`,
  // `AddEditBudgetView+SpecificDates.swift`, and `AddEditBudgetView+Schedule.swift`
  // can't see `private` members. Treat them as if they were `private` to this view
  // — do not consume from unrelated call sites.
  @State var viewModel: AddEditBudgetViewModel
  @Environment(\.modelContext) private var context
  @Environment(AppSettings.self) var settings
  @Environment(Router.self) private var router
  @Environment(\.analytics) private var analytics
  @Environment(\.dismiss) private var dismiss

  @State var showCurrencyPicker = false
  @State private var showDeleteConfirmation = false
  @State private var showOrphanWarning = false
  /// Save-time confirmation shown when a biweekly budget's start date is edited, since
  /// that re-anchors the 14-day grid and recalculates past periods (and carry-over).
  @State private var showBiweeklyReanchorWarning = false
  @State private var showIconPicker = false
  /// Standard save-error alert state (`persistence-error-handling` capability).
  /// Populated when `viewModel.save`/`viewModel.delete` throws a
  /// `PersistenceError`; the sheet stays open with input intact.
  @State private var saveError: SaveErrorState?
  @State var initialCurrencyCode: String = ""
  @State var isScheduleExpanded: Bool = false
  /// Non-`private` for cross-file extension access — see the note above. The allocation
  /// card (in `+AllocationCard.swift`) clears this when its amount field begins editing.
  @FocusState var isNameFocused: Bool

  private var isSpecificDates: Bool {
    viewModel.period == .specificDates
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 16) {
          nameCard
          allocationCard
          periodCard
          if isSpecificDates {
            datesCard
          } else {
            scheduleCard
            carryOverCard
          }
          if viewModel.isEditing {
            deleteButton
          }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 32)
        .animation(.easeInOut(duration: 0.2), value: isSpecificDates)
      }
      .scrollDismissesKeyboard(.interactively)
      .onAppear {
        initialCurrencyCode = viewModel.currencyCode
        if !viewModel.isEditing {
          isNameFocused = true
        }
        if viewModel.orphanedExpenseCount > 0 {
          isScheduleExpanded = true
        }
        // Biweekly cycles anchor to the start date, so surface it on open.
        if viewModel.period == .biweekly {
          isScheduleExpanded = true
        }
      }
      // When the global week-start changes, re-anchor the Add-mode weekly draft's
      // startDate to match the new grid (no-op in Edit mode / non-weekly — see
      // realignWeeklyStartDate).
      .onChange(of: settings.weekStartDay) { _, newValue in
        viewModel.realignWeeklyStartDate(to: newValue)
      }
      .navigationTitle(
        viewModel.isEditing
          ? String(
            localized: "addEditBudget.title.edit",
            defaultValue: "Edit Budget",
            comment: "Navigation bar title when editing an existing budget"
          )
          : String(
            localized: "addEditBudget.title.add",
            defaultValue: "New Budget",
            comment: "Navigation bar title when creating a new budget"
          )
      )
      .navigationBarTitleDisplayMode(.inline)
      .appBackground()
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(String(
            localized: "addEditBudget.action.cancel",
            defaultValue: "Cancel",
            comment: "Button that dismisses the Add/Edit Budget sheet without saving"
          )) {
            dismiss()
          }
          .tint(.accentColor)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(String(
            localized: "addEditBudget.action.save",
            defaultValue: "Save",
            comment: "Button that saves the budget and dismisses the Add/Edit Budget sheet"
          )) {
            if viewModel.isBiweeklyStartDateEdited {
              // Biweekly re-anchor confirmation; its message folds in the orphan
              // sentence when expenses are also stranded, so we never stack alerts.
              showBiweeklyReanchorWarning = true
            } else if viewModel.orphanedExpenseCount > 0 {
              showOrphanWarning = true
            } else {
              commitSave()
            }
          }
          .disabled(!viewModel.canSave)
          .fontWeight(.semibold)
          .tint(.accentColor)
        }
      }
      .sheet(isPresented: $showCurrencyPicker) {
        CurrencyPickerView(selection: $viewModel.currencyCode)
      }
      .saveErrorAlert($saveError)
      .alert(
        String(
          localized: "addEditBudget.orphanWarning.title",
          defaultValue: "Start date is after \(viewModel.orphanedExpenseCount) logged expenses",
          comment: "Title of the alert shown when the user taps Save on Edit Budget and the drafted startDate is after at least one already-logged expense's date. The Int argument is the count of orphaned expenses."
        ),
        isPresented: $showOrphanWarning
      ) {
        Button(String(
          localized: "addEditBudget.orphanWarning.cancel",
          defaultValue: "Cancel",
          comment: "Cancel button on the orphan-expense alert; returns the user to the Edit Budget form with draft state preserved."
        ), role: .cancel) {}
        Button(String(
          localized: "addEditBudget.orphanWarning.confirm",
          defaultValue: "Save Changes",
          comment: "Confirm button on the orphan-expense alert; commits the Save and dismisses the Edit Budget sheet."
        )) { commitSave() }
      } message: {
        Text(String(
          localized: "addEditBudget.orphanWarning.message",
          defaultValue: "Those expenses still show in your list but won't be counted by this budget.",
          comment: "Body of the orphan-expense alert on the Edit Budget Save confirmation. Explains that orphaned expenses stay in the list but are not counted by the budget."
        ))
      }
      .alert(
        String(
          localized: "addEditBudget.biweeklyReanchor.title",
          defaultValue: "Change Start Date?",
          comment: "Title of the confirmation alert shown when the user taps Save on Edit Budget after changing a biweekly budget's start date. Changing it re-anchors the 14-day cycle grid."
        ),
        isPresented: $showBiweeklyReanchorWarning
      ) {
        Button(String(
          localized: "addEditBudget.biweeklyReanchor.cancel",
          defaultValue: "Cancel",
          comment: "Cancel button on the biweekly re-anchor alert; returns the user to the Edit Budget form with draft state preserved."
        ), role: .cancel) {}
        Button(String(
          localized: "addEditBudget.biweeklyReanchor.confirm",
          defaultValue: "Change",
          comment: "Confirm button on the biweekly re-anchor alert; commits the Save and dismisses the Edit Budget sheet."
        )) { commitSave() }
      } message: {
        Text(biweeklyReanchorMessage)
      }
    }
  }

  /// Body for the biweekly re-anchor confirmation. The base sentence explains the
  /// re-alignment; when the same edit also strands logged expenses, the orphan
  /// sentence is appended so both consequences land in a single alert.
  private var biweeklyReanchorMessage: String {
    let base = String(
      localized: "addEditBudget.biweeklyReanchor.message",
      defaultValue: "This will re-align current and future two-week cycles and recalculate past periods.",
      comment: "Body of the biweekly re-anchor alert on the Edit Budget Save confirmation. Warns that changing the start date re-aligns the 14-day cycles and recalculates past periods (and carry-over)."
    )
    guard viewModel.orphanedExpenseCount > 0 else { return base }
    let orphan = String(
      localized: "addEditBudget.orphanWarning.message",
      defaultValue: "Those expenses still show in your list but won't be counted by this budget.",
      comment: "Body of the orphan-expense alert on the Edit Budget Save confirmation. Explains that orphaned expenses stay in the list but are not counted by the budget."
    )
    return "\(base) \(orphan)"
  }

  private func commitSave() {
    do {
      try viewModel.save(context: context, analytics: analytics, settings: settings, router: router)
      saveError.clear()
      dismiss()
    } catch let error as PersistenceError {
      // Per `add-edit-budget-screen` delta spec: sheet stays open with input
      // intact; alert presents Retry; the inserted-but-unsaved Budget remains
      // in the context so Retry re-attempts the same save.
      saveError.setForFailure(error, retry: commitSave)
    } catch {
      // saveChanges only throws PersistenceError; exhaustive catch for safety.
    }
  }

  private func commitDelete() {
    do {
      try viewModel.delete(context: context, analytics: analytics)
      saveError.clear()
      router.path.removeAll()
      dismiss()
    } catch let error as PersistenceError {
      saveError.setForFailure(error, retry: commitDelete)
    } catch {
      // saveChanges only throws PersistenceError; exhaustive catch for safety.
    }
  }

  // MARK: - Destructive Actions

  private var deleteButton: some View {
    Button(role: .destructive) {
      showDeleteConfirmation = true
    } label: {
      Text(String(
        localized: "addEditBudget.action.delete",
        defaultValue: "Delete Budget",
        comment: "Button that triggers the delete budget confirmation dialog"
      ))
      .frame(maxWidth: .infinity)
    }
    .buttonStyle(.bordered)
    .tint(.red)
    .accessibilityHint(String(
      localized: "addEditBudget.action.delete.accessibilityHint",
      defaultValue: "Permanently deletes this budget and its expenses.",
      comment: "VoiceOver hint for the Delete Budget button, communicating the destructive and irreversible consequence"
    ))
    .confirmationDialog(
      String(
        localized: "addEditBudget.deleteConfirmation.title",
        defaultValue: "Delete Budget?",
        comment: "Title of the confirmation dialog when the user taps Delete Budget"
      ),
      isPresented: $showDeleteConfirmation,
      titleVisibility: .visible
    ) {
      Button(
        String(
          localized: "addEditBudget.deleteConfirmation.confirm",
          defaultValue: "Delete Budget",
          comment: "Destructive confirm button in the delete budget confirmation dialog"
        ),
        role: .destructive
      ) {
        commitDelete()
      }
    } message: {
      Text(String(
        localized: "addEditBudget.deleteConfirmation.message",
        defaultValue: "This action cannot be undone.",
        comment: "Body text in the delete budget confirmation dialog warning that deletion is permanent"
      ))
    }
  }

  // MARK: - Cards

  private var nameCard: some View {
    GroupBox {
      HStack(spacing: 8) {
        iconField
        TextField(
          String(
            localized: "addEditBudget.field.name.placeholder",
            defaultValue: "Budget",
            comment: "Placeholder text for the budget name field"
          ),
          text: $viewModel.name
        )
        .font(.title2)
        .focused($isNameFocused)
        .accessibilityLabel(String(
          localized: "addEditBudget.field.name.accessibilityLabel",
          defaultValue: "Budget name",
          comment: "VoiceOver label for the budget name text field"
        ))
      }
    } label: {
      sectionLabel(String(
        localized: "addEditBudget.section.name",
        defaultValue: "Name",
        comment: "Section header above the budget name field"
      ))
    }
    .backgroundStyle(Color("CellBackground"))
  }

  private var hasIcon: Bool {
    !(viewModel.icon ?? "").isEmpty
  }

  /// Optional icon prefix. A tappable chip that opens the budget icon picker
  /// (`BudgetIconPicker`, a curated emoji grid). Shows the chosen icon, or an
  /// accent-tinted smiley placeholder inviting the user to pick one. The accent
  /// wash only appears in the empty state — a chosen emoji renders in its own
  /// colors, so the chip reverts to the neutral fill.
  private var iconField: some View {
    Button {
      showIconPicker = true
    } label: {
      Group {
        if let icon = viewModel.icon, !icon.isEmpty {
          Text(verbatim: icon)
        } else {
          Image(systemName: "face.smiling")
            .foregroundStyle(Color.accentColor)
        }
      }
      .font(.title3)
      .frame(minWidth: 44, minHeight: 44)
      .background(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(hasIcon ? Color.secondary.opacity(0.12) : Color.accentColor.opacity(0.12))
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(String(
      localized: "addEditBudget.field.icon.accessibilityLabel",
      defaultValue: "Budget icon",
      comment: "VoiceOver label for the optional icon chip shown before the budget name field"
    ))
    .accessibilityValue(viewModel.icon ?? String(
      localized: "addEditBudget.field.icon.accessibilityValue.none",
      defaultValue: "None",
      comment: "VoiceOver value announced for the budget icon chip when no icon is chosen"
    ))
    .accessibilityHint(String(
      localized: "addEditBudget.field.icon.accessibilityHint",
      defaultValue: "Opens a picker to choose an icon for the budget.",
      comment: "VoiceOver hint for the optional budget icon chip"
    ))
    .sheet(isPresented: $showIconPicker) {
      BudgetIconPicker(selection: $viewModel.icon)
    }
  }

  private var periodCard: some View {
    GroupBox {
      let columns = [GridItem(.flexible()), GridItem(.flexible())]
      VStack(alignment: .leading, spacing: 8) {
        LazyVGrid(columns: columns, spacing: 8) {
          ForEach([BudgetPeriod.daily, .weekly, .biweekly, .monthly], id: \.self) { p in
            periodChip(p)
          }
        }
        .padding(.top, 4)
        periodChip(.specificDates)

        if isSpecificDates {
          Text(String(
            localized: "addEditBudget.note.specificDates",
            defaultValue: "Good for a trip, a birthday weekend, or any one-off spending window. When it's done, it's done. No repeating, no carry-over.",
            comment: "Caption shown below the Specific Dates period chip explaining that this budget type is non-recurring with no carry-over"
          ))
          .font(.caption)
          .foregroundStyle(.readableSecondary)
          .padding(.top, 4)
          .transition(.opacity.combined(with: .move(edge: .top)))
        }

        if viewModel.period == .biweekly {
          Text(String(
            localized: "addEditBudget.note.biweekly",
            defaultValue: "Repeating 14-day period. Choose your start date below to choose which day each cycle begins on.",
            comment: "Caption below the period chip grid when Biweekly is selected. Explains the 14-day cycle is anchored to the budget's start date, so the start date sets which day each cycle begins on."
          ))
          .font(.caption)
          .foregroundStyle(.readableSecondary)
          .padding(.top, 4)
          .transition(.opacity.combined(with: .move(edge: .top)))
        }

        if viewModel.period == .weekly {
          weeklyNote
        }

        if viewModel.isEditing {
          Label(
            String(
              localized: "addEditBudget.note.periodLocked",
              defaultValue: "Period type can't be changed after creating your budget.",
              comment: "Caption below the period chip grid in edit mode, explaining that the period is locked"
            ),
            systemImage: "lock.fill"
          )
          .font(.caption)
          .foregroundStyle(.readableSecondary)
          .padding(.top, 8)
        }
      }
      .animation(.easeInOut(duration: 0.2), value: viewModel.period)
    } label: {
      sectionLabel(String(
        localized: "addEditBudget.section.period",
        defaultValue: "Period",
        comment: "Section header above the budget period chip grid"
      ))
    }
    .backgroundStyle(Color("CellBackground"))
  }

  private var carryOverCard: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 0) {
        Toggle(isOn: $viewModel.isCarryOverEnabled) {
          Text(String(
            localized: "addEditBudget.section.carryOver",
            defaultValue: "Carry-Over",
            comment: "Toggle label and section header for the carry-over setting on the Add/Edit Budget screen"
          ))
          .font(.title3)
          .foregroundStyle(.primary)
          .accessibilityIdentifier("srb.sectionLabel")
        }
        .tint(.accentColor)
        .accessibilityHint(String(
          localized: "addEditBudget.toggle.carryOver.accessibilityHint",
          defaultValue: "When on, unspent or overspent amounts carry forward across periods",
          comment: "VoiceOver hint for the carry-over toggle on the Add/Edit Budget screen"
        ))

        Text(String(
          localized: "addEditBudget.note.carryOver",
          defaultValue: "Cumulative over- and under-spending across periods.",
          comment: "Caption below the carry-over toggle explaining what carry-over does"
        ))
        .font(.caption)
        .foregroundStyle(.primary)
        .padding(.top, 8)
        .accessibilityIdentifier("srb.sectionLabel")
      }
      .animation(.easeInOut(duration: 0.2), value: viewModel.isCarryOverEnabled)
    } label: {
      sectionLabel(String(
        localized: "addEditBudget.section.carryOver",
        defaultValue: "Carry-Over",
        comment: "Toggle label and section header for the carry-over setting on the Add/Edit Budget screen"
      ))
    }
    .backgroundStyle(Color("CellBackground"))
  }

  // MARK: - Period chip

  @ViewBuilder
  private func periodChip(_ p: BudgetPeriod) -> some View {
    let isSelected = viewModel.period == p

    if viewModel.isEditing {
      Text(p.listLabel)
        .font(.subheadline)
        .fontWeight(isSelected ? .semibold : .regular)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isSelected ? Color.accentFill : Color.secondary.opacity(0.06))
        )
        // 0.3 is below WCAG AA contrast on purpose: in edit mode the period is
        // immutable, and the washed-out chips are the disabled-state affordance
        // (SC 1.4.3 exempts inactive controls; VoiceOver announces "Locked.").
        // No accessibility audit covers the edit-mode form (issue #223 survey).
        .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.3))
        .accessibilityLabel(String(
          localized: "addEditBudget.chip.period.accessibilityLabel",
          defaultValue: "\(p.listLabel) period",
          comment: "VoiceOver label for a period selection chip; argument is the period name (Daily, Weekly, etc.)"
        ))
        .accessibilityHint(String(
          localized: "addEditBudget.chip.period.locked.accessibilityHint",
          defaultValue: "Locked. Period type can't be changed after creating your budget.",
          comment: "VoiceOver hint for a period chip in Edit mode; tells the user the period is immutable post-creation"
        ))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    } else {
      Button {
        // A Period chip is not a text field, so selecting one should retire the keyboard
        // left up by prior name/allocation editing — otherwise it covers the Dates card
        // that appears when switching to Specific Dates.
        dismissKeyboard()
        withAnimation(.easeInOut(duration: 0.15)) {
          viewModel.period = p
          // Biweekly cycles anchor to the start date — auto-reveal it (never auto-collapse).
          if p == .biweekly {
            isScheduleExpanded = true
          }
        }
      } label: {
        Text(p.listLabel)
          .font(.subheadline)
          .fontWeight(isSelected ? .semibold : .regular)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 10)
          .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .fill(isSelected ? Color.accentFill : Color.secondary.opacity(0.1))
          )
          .foregroundStyle(isSelected ? Color.white : Color.primary)
      }
      .buttonStyle(.plain)
      .accessibilityLabel(String(
        localized: "addEditBudget.chip.period.accessibilityLabel",
        defaultValue: "\(p.listLabel) period",
        comment: "VoiceOver label for a period selection chip; argument is the period name (Daily, Weekly, etc.)"
      ))
      .accessibilityAddTraits(isSelected ? .isSelected : [])
      // Locale-invariant handle so UI tests can tap a specific period (e.g. the
      // AppStoreScreenshots capture taps `budgetPeriod.daily` to dismiss the
      // auto-keyboard deterministically without changing the selection).
      .accessibilityIdentifier("budgetPeriod.\(p.rawValue)")
    }
  }

  // MARK: - Helpers

  /// Internal: cross-file extension access only. See the comment on `viewModel` at the
  /// top of this struct — used by `+AllocationCard.swift` and `+SpecificDates.swift`.
  func sectionLabel(_ text: String) -> some View {
    Text(text)
      .font(.subheadline)
      .foregroundStyle(Color.primary.opacity(0.75))
      .accessibilityIdentifier("srb.sectionLabel")
  }
}
