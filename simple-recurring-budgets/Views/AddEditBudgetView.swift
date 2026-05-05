import SwiftData
import SwiftUI

struct AddEditBudgetView: View {
  @State var viewModel: AddEditBudgetViewModel
  @Environment(\.modelContext) private var context
  @Environment(AppSettings.self) private var settings
  @Environment(Router.self) private var router
  @Environment(\.analytics) private var analytics
  @Environment(\.dismiss) private var dismiss

  @State private var showCurrencyPicker = false
  @State private var showDeleteConfirmation = false
  @State private var initialCurrencyCode: String = ""
  @FocusState private var isNameFocused: Bool

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 16) {
          nameCard
          allocationCard
          periodCard
          carryOverCard
          if viewModel.isEditing {
            deleteButton
          }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 32)
      }
      .onAppear {
        initialCurrencyCode = viewModel.currencyCode
        if !viewModel.isEditing {
          isNameFocused = true
        }
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
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(String(
            localized: "addEditBudget.action.save",
            defaultValue: "Save",
            comment: "Button that saves the budget and dismisses the Add/Edit Budget sheet"
          )) {
            viewModel.save(context: context, analytics: analytics, settings: settings, router: router)
            dismiss()
          }
          .disabled(!viewModel.canSave)
          .fontWeight(.semibold)
        }
      }
      .sheet(isPresented: $showCurrencyPicker) {
        CurrencyPickerView(selection: $viewModel.currencyCode)
      }
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
        viewModel.delete(context: context, analytics: analytics)
        dismiss()
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
      TextField(
        String(
          localized: "addEditBudget.field.name.placeholder",
          defaultValue: "Budget",
          comment: "Placeholder text for the budget name field"
        ),
        text: $viewModel.name
      )
      .font(.body)
      .focused($isNameFocused)
      .accessibilityLabel(String(
        localized: "addEditBudget.field.name.accessibilityLabel",
        defaultValue: "Budget name",
        comment: "VoiceOver label for the budget name text field"
      ))
    } label: {
      sectionLabel(String(
        localized: "addEditBudget.section.name",
        defaultValue: "Name",
        comment: "Section header above the budget name field"
      ))
    }
    .backgroundStyle(Color("CellBackground"))
  }

  private var allocationCard: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 8) {
        HStack(alignment: .center, spacing: 12) {
          HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(currencyPrefix)
              .font(.title2.weight(.semibold))
              .foregroundStyle(.secondary)
            TextField(
              String(
                localized: "addEditBudget.field.allocation.placeholder",
                defaultValue: "0",
                comment: "Placeholder in the allocation amount field when no value is entered"
              ),
              value: $viewModel.allocation,
              format: OptionalDecimalFormatStyle()
            )
            .keyboardType(.decimalPad)
            .font(.title2.weight(.semibold).monospacedDigit())
            .accessibilityLabel(
              String(
                localized: "addEditBudget.field.allocation.accessibilityLabel",
                defaultValue: "Allocation amount, \((viewModel.allocation ?? 0).formatted(currencyCode: viewModel.currencyCode, display: settings.currencyDisplay))",
                comment: "VoiceOver label for the allocation field; argument is the formatted monetary amount including currency"
              )
            )
          }
          .frame(maxWidth: .infinity, alignment: .leading)

          Button {
            showCurrencyPicker = true
          } label: {
            HStack(spacing: 4) {
              Text(viewModel.currencyCode)
                .font(.callout.weight(.medium))
              Image(systemName: "chevron.up.chevron.down")
                .font(.caption2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.secondary.opacity(0.12)))
            .foregroundStyle(.secondary)
          }
          .buttonStyle(.plain)
          .accessibilityLabel(String(
            localized: "addEditBudget.field.currency.accessibilityLabel",
            defaultValue: "Currency, \(viewModel.currencyCode)",
            comment: "VoiceOver label for the currency selection pill showing the current ISO code"
          ))
          .accessibilityHint(String(
            localized: "addEditBudget.field.currency.accessibilityHint",
            defaultValue: "Opens currency picker",
            comment: "VoiceOver hint for the currency selection pill"
          ))
        }

        if !initialCurrencyCode.isEmpty, viewModel.currencyCode != initialCurrencyCode {
          Text(String(
            localized: "addEditBudget.note.currencyLabelOnly",
            defaultValue: "Changing currency only updates the label. I.e. No currency conversion.",
            comment: "Inline note shown below the currency picker when the user selects a different currency, warning that no conversion is applied"
          ))
          .font(.caption)
          .foregroundStyle(.secondary)
          .transition(.opacity.combined(with: .move(edge: .top)))
        }
      }
      .animation(.easeInOut(duration: 0.2), value: viewModel.currencyCode)
    } label: {
      sectionLabel(String(
        localized: "addEditBudget.section.allocation",
        defaultValue: "Allocation",
        comment: "Section header above the allocation amount and currency fields"
      ))
    }
    .backgroundStyle(Color("CellBackground"))
    .onChange(of: viewModel.currencyCode) { _, newCode in
      guard !initialCurrencyCode.isEmpty, newCode != initialCurrencyCode else { return }
      let disclaimer = String(
        localized: "addEditBudget.note.currencyLabelOnly",
        defaultValue: "Changing currency only updates the label. I.e. No currency conversion.",
        comment: "Inline note shown below the currency picker when the user selects a different currency, warning that no conversion is applied"
      )
      AccessibilityNotification.Announcement(disclaimer).post()
    }
  }

  private var periodCard: some View {
    GroupBox {
      let columns = [GridItem(.flexible()), GridItem(.flexible())]
      VStack(alignment: .leading, spacing: 8) {
        LazyVGrid(columns: columns, spacing: 8) {
          ForEach(BudgetPeriod.allCases, id: \.self) { p in
            periodChip(p)
          }
        }

        if viewModel.isEditing {
          Label(
            String(
              localized: "addEditBudget.note.periodLocked",
              defaultValue: "This can't be changed after creating your budget.",
              comment: "Caption below the period chip grid in edit mode, explaining that the period is locked"
            ),
            systemImage: "lock.fill"
          )
          .font(.caption)
          .foregroundStyle(.secondary)
          .padding(.top, 8)
        }
      }
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
        Toggle(
          String(
            localized: "addEditBudget.section.carryOver",
            defaultValue: "Carry-Over",
            comment: "Toggle label and section header for the carry-over setting on the Add/Edit Budget screen"
          ),
          isOn: $viewModel.isCarryOverEnabled
        )
        .tint(.accentColor)
        .accessibilityHint(String(
          localized: "addEditBudget.toggle.carryOver.accessibilityHint",
          defaultValue: "When on, unspent or overspent amounts carry forward across periods",
          comment: "VoiceOver hint for the carry-over toggle on the Add/Edit Budget screen"
        ))

        Text(String(
          localized: "addEditBudget.note.carryOver",
          defaultValue: "Accumulates unspent or overspent amounts over time.",
          comment: "Caption below the carry-over toggle explaining what carry-over does"
        ))
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.top, 8)
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
            .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.06))
        )
        .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.3))
        .accessibilityLabel(String(
          localized: "addEditBudget.chip.period.accessibilityLabel",
          defaultValue: "\(p.listLabel) period",
          comment: "VoiceOver label for a period selection chip; argument is the period name (Daily, Weekly, etc.)"
        ))
        .accessibilityHint(String(
          localized: "addEditBudget.chip.period.locked.accessibilityHint",
          defaultValue: "Locked. Period can't be changed after creating your budget.",
          comment: "VoiceOver hint for a period chip in Edit mode; tells the user the period is immutable post-creation"
        ))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    } else {
      Button {
        withAnimation(.easeInOut(duration: 0.15)) {
          viewModel.period = p
        }
      } label: {
        Text(p.listLabel)
          .font(.subheadline)
          .fontWeight(isSelected ? .semibold : .regular)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 10)
          .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.1))
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
    }
  }

  // MARK: - Helpers

  private var currencyPrefix: String {
    settings.currencyDisplay.prefix(for: viewModel.currencyCode)
  }

  private func sectionLabel(_ text: String) -> some View {
    Text(text)
      .font(.subheadline)
      .foregroundStyle(.secondary)
  }
}

// MARK: - Previews

#if DEBUG
  #Preview("Add — Light") {
    AddEditBudgetView(viewModel: AddEditBudgetViewModel(settings: AppSettings()))
      .modelContainer(PreviewContainer.make())
      .environment(AppSettings())
      .environment(Router())
  }

  #Preview("Add — Dark") {
    AddEditBudgetView(viewModel: AddEditBudgetViewModel(settings: AppSettings()))
      .modelContainer(PreviewContainer.make())
      .environment(AppSettings())
      .environment(Router())
      .preferredColorScheme(.dark)
  }

  #Preview("Edit — Light") {
    let budget = DebugData.dailyDefault()
    return AddEditBudgetView(viewModel: AddEditBudgetViewModel(editing: budget))
      .modelContainer(PreviewContainer.make())
      .environment(AppSettings())
      .environment(Router())
  }

  #Preview("Edit — Dark") {
    let budget = DebugData.monthlyDefault()
    return AddEditBudgetView(viewModel: AddEditBudgetViewModel(editing: budget))
      .modelContainer(PreviewContainer.make())
      .environment(AppSettings())
      .environment(Router())
      .preferredColorScheme(.dark)
  }

  #Preview("xxxLarge Type") {
    let budget = DebugData.weeklyDefault()
    return AddEditBudgetView(viewModel: AddEditBudgetViewModel(editing: budget))
      .modelContainer(PreviewContainer.make())
      .environment(AppSettings())
      .environment(Router())
      .dynamicTypeSize(.xxxLarge)
  }

  #Preview("Empty — Save disabled") {
    let vm = AddEditBudgetViewModel(settings: AppSettings())
    vm.name = ""
    vm.allocation = nil
    return AddEditBudgetView(viewModel: vm)
      .modelContainer(PreviewContainer.make())
      .environment(AppSettings())
      .environment(Router())
  }
#endif
