import SwiftData
import SwiftUI

// MARK: - View

struct AddEditExpenseView: View {
  @State var viewModel: AddEditExpenseViewModel
  @Environment(\.modelContext) private var context
  @Environment(AppSettings.self) var settings
  @Environment(\.analytics) private var analytics
  @Environment(\.dismiss) private var dismiss
  /// F-6.03 rating-prompt coordinator. Not `private` — read by
  /// `notifyRatingPromptIfNeeded()` in `AddEditExpenseView+RatingPrompt.swift`.
  /// Optional so Previews / unit hosts that don't inject it no-op rather than crash.
  @Environment(RatingPromptCoordinator.self) var ratingPrompt: RatingPromptCoordinator?

  @State private var showDeleteConfirmation = false
  /// Standard save-error alert state (`persistence-error-handling` capability).
  @State private var saveError: SaveErrorState?

  var body: some View {
    ScrollView {
      VStack(spacing: 16) {
        amountCard
        nameCard
        recentsSection
        whenCard
        addFundsCard
        if viewModel.isEditing {
          deleteButton
        }
      }
      .padding(.horizontal)
      .padding(.top, 8)
      .padding(.bottom, 32)
    }
    .navigationTitle(viewModel.navigationTitle)
    .navigationBarTitleDisplayMode(.inline)
    .appBackground()
    .toolbar {
      if !viewModel.isEditing {
        ToolbarItem(placement: .cancellationAction) {
          Button(String(
            localized: "addEditExpense.action.cancel",
            defaultValue: "Cancel",
            comment: "Button that dismisses the Add/Edit Expense sheet without saving"
          )) {
            dismiss()
          }
          .tint(.accentColor)
        }
      }
      ToolbarItem(placement: .confirmationAction) {
        Button(String(
          localized: "addEditExpense.action.save",
          defaultValue: "Save",
          comment: "Button that saves the expense and dismisses the sheet"
        )) {
          commitSave()
        }
        .disabled(!viewModel.canSave)
        .fontWeight(.semibold)
        .tint(.accentColor)
      }
    }
    .saveErrorAlert($saveError)
  }

  private func commitSave() {
    do {
      try viewModel.save(context: context, analytics: analytics)
      saveError.clear()
      notifyRatingPromptIfNeeded()
      dismiss()
    } catch let error as PersistenceError {
      // Per `add-edit-expense-screen` delta spec: sheet stays open with input
      // intact; expense_logged/expense_edited not fired on failure.
      saveError.setForFailure(error, retry: commitSave)
    } catch {
      // saveChanges only throws PersistenceError; exhaustive catch for safety.
    }
  }

  private func commitDelete() {
    do {
      try viewModel.delete(context: context, analytics: analytics)
      saveError.clear()
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
        localized: "addEditExpense.action.delete",
        defaultValue: "Delete Expense",
        comment: "Button that triggers the delete expense confirmation dialog"
      ))
      .frame(maxWidth: .infinity)
    }
    .buttonStyle(.bordered)
    .tint(.red)
    .accessibilityHint(String(
      localized: "addEditExpense.action.delete.accessibilityHint",
      defaultValue: "Permanently deletes this expense.",
      comment: "VoiceOver hint for the Delete Expense button"
    ))
    .confirmationDialog(
      String(
        localized: "addEditExpense.deleteConfirmation.title",
        defaultValue: "Delete Expense?",
        comment: "Title of the confirmation dialog when the user taps Delete Expense"
      ),
      isPresented: $showDeleteConfirmation,
      titleVisibility: .visible
    ) {
      Button(
        String(
          localized: "addEditExpense.deleteConfirmation.confirm",
          defaultValue: "Delete Expense",
          comment: "Destructive confirm button in the delete expense confirmation dialog"
        ),
        role: .destructive
      ) {
        commitDelete()
      }
    } message: {
      Text(String(
        localized: "addEditExpense.deleteConfirmation.message",
        defaultValue: "This action cannot be undone.",
        comment: "Body text in the delete expense confirmation dialog"
      ))
    }
  }

  // MARK: - Cards

  private var nameCard: some View {
    GroupBox {
      // Mirrors CurrencyAmountField's trailing-✕ pattern so the two text inputs clear
      // the same way. Clearing also resets the Recents filter below, restoring the
      // full suggestion row.
      HStack(alignment: .center, spacing: 2) {
        TextField(
          String(
            localized: "addEditExpense.field.name.placeholder",
            defaultValue: "e.g. Coffee",
            comment: "Placeholder text for the expense description field"
          ),
          text: $viewModel.name
        )
        .font(.body)
        .accessibilityLabel(String(
          localized: "addEditExpense.field.name.accessibilityLabel",
          defaultValue: "Expense description",
          comment: "VoiceOver label for the expense description text field"
        ))
        if !viewModel.name.isEmpty {
          Button {
            viewModel.name = ""
          } label: {
            Image(systemName: "xmark.circle.fill")
              .foregroundStyle(.secondary)
              .font(.body)
          }
          .buttonStyle(.plain)
          .accessibilityLabel(String(
            localized: "addEditExpense.field.name.clearButton.accessibilityLabel",
            defaultValue: "Clear description",
            comment: "VoiceOver label for the trailing clear button in the expense description field"
          ))
        }
      }
    } label: {
      sectionLabel(String(
        localized: "addEditExpense.section.name",
        defaultValue: "Description (optional)",
        comment: "Section header above the expense description field"
      ))
    }
    .backgroundStyle(Color("CellBackground"))
  }

  private var whenCard: some View {
    GroupBox {
      VStack(alignment: .leading) {
        DatePicker(
          selection: $viewModel.date,
          in: viewModel.dateRange,
          displayedComponents: [.date, .hourAndMinute]
        ) {
          EmptyView()
        }
        .datePickerStyle(.compact)
        .labelsHidden()
        .accessibilityLabel(String(
          localized: "addEditExpense.field.date.label",
          defaultValue: "When",
          comment: "VoiceOver label for the expense date and time picker (the visible section header above it carries the same word)"
        ))
        if let caption = viewModel.dateContextCaption {
          Text(caption)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 3)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    } label: {
      sectionLabel(String(
        localized: "addEditExpense.section.when",
        defaultValue: "When",
        comment: "Section header above the expense date and time picker"
      ))
    }
    .backgroundStyle(Color("CellBackground"))
  }

  // MARK: - Helpers

  func sectionLabel(_ text: String) -> some View {
    Text(text)
      .font(.subheadline)
      .foregroundStyle(Color.primary)
      .accessibilityIdentifier("srb.sectionLabel")
  }
}

// Previews live in `AddEditExpenseView+Previews.swift` so this file stays under
// the project's 600-line per-file lint cap.
