import SwiftUI

// MARK: - Dates card (Specific Dates period)

extension AddEditBudgetView {
  var datesCard: some View {
    GroupBox {
      HStack(alignment: .top, spacing: 12) {
        DateColumn(
          placeholder: String(
            localized: "addEditBudget.field.date.start.placeholder",
            defaultValue: "Choose start date",
            comment: "Placeholder shown on the empty start-date chip in the Add/Edit Budget Dates card when the Specific Dates period is selected"
          ),
          accessibilityHint: String(
            localized: "addEditBudget.field.date.start.accessibilityHint",
            defaultValue: "Opens a calendar to pick the start date.",
            comment: "VoiceOver hint for the start-date chip in the Add/Edit Budget Dates card"
          ),
          setStateAccessibilityLabel: { date in
            String(
              localized: "addEditBudget.field.date.start.accessibilityLabel.set",
              defaultValue: "Start date, \(date.formatted(date: .abbreviated, time: .omitted))",
              comment: "VoiceOver label for the start-date chip when a date is set; argument is the formatted date"
            )
          },
          date: $viewModel.startDate,
          minDate: nil
        )
        DateColumn(
          placeholder: String(
            localized: "addEditBudget.field.date.end.placeholder",
            defaultValue: "Choose end date",
            comment: "Placeholder shown on the empty end-date chip in the Add/Edit Budget Dates card when the Specific Dates period is selected"
          ),
          accessibilityHint: String(
            localized: "addEditBudget.field.date.end.accessibilityHint",
            defaultValue: "Opens a calendar to pick the end date.",
            comment: "VoiceOver hint for the end-date chip in the Add/Edit Budget Dates card"
          ),
          setStateAccessibilityLabel: { date in
            String(
              localized: "addEditBudget.field.date.end.accessibilityLabel.set",
              defaultValue: "End date, \(date.formatted(date: .abbreviated, time: .omitted))",
              comment: "VoiceOver label for the end-date chip when a date is set; argument is the formatted date"
            )
          },
          date: $viewModel.endDate,
          minDate: viewModel.startDate
        )
      }
      .padding(.top, 4)
      .animation(.easeInOut(duration: 0.15), value: viewModel.startDate)
      .animation(.easeInOut(duration: 0.15), value: viewModel.endDate)
    } label: {
      sectionLabel(String(
        localized: "addEditBudget.section.dates",
        defaultValue: "Dates",
        comment: "Section header for the start/end dates card on the Add/Edit Budget sheet when Specific Dates is selected"
      ))
    }
    .backgroundStyle(Color("CellBackground"))
  }
}

// MARK: - DateColumn

/// Date chip + sheet picker for the Add/Edit Budget date cards: a full-width rounded chip
/// (placeholder when empty, abbreviated locale date once set) that opens a sheet with a
/// `.graphical` `DatePicker`; Cancel discards, Done assigns.
///
/// Not reusable as-is: the placeholder, hint, and label closure are wired to localization
/// keys specific to these cards. Extract a shell first if another site needs one.
struct DateColumn: View {
  let placeholder: String
  let accessibilityHint: String
  let setStateAccessibilityLabel: (Date) -> String
  @Binding var date: Date?
  let minDate: Date?

  @State private var isPickerShown = false
  @State private var draft: Date = .init()

  var body: some View {
    Button {
      // Retire any keyboard before the sheet covers it; otherwise iOS restores the prior
      // first responder on dismiss and the keyboard springs back up over the form.
      dismissKeyboard()
      // Defensive: floors the draft at minDate so it can't fall below the picker's range.
      // The VM's snap-forward normally keeps `date >= minDate`; don't remove this guard.
      let floor = minDate ?? .distantPast
      draft = max(date ?? minDate ?? Date(), floor)
      isPickerShown = true
    } label: {
      Text(displayText)
        .font(.subheadline)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.secondary.opacity(0.1))
        )
        .foregroundStyle(Color.accentColor)
    }
    .buttonStyle(.plain)
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityLabel(accessibilityLabel)
    .accessibilityHint(accessibilityHint)
    .sheet(isPresented: $isPickerShown) {
      pickerSheet
    }
  }

  private var displayText: String {
    if let date {
      return date.formatted(date: .abbreviated, time: .omitted)
    }
    return placeholder
  }

  private var accessibilityLabel: String {
    if let date {
      return setStateAccessibilityLabel(date)
    }
    return placeholder
  }

  private var pickerSheet: some View {
    NavigationStack {
      DatePicker(
        selection: $draft,
        in: (minDate ?? .distantPast) ... Date.distantFuture,
        displayedComponents: .date
      ) {
        EmptyView()
      }
      .datePickerStyle(.graphical)
      .labelsHidden()
      .padding()
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(String(
            localized: "addEditBudget.dates.picker.cancel",
            defaultValue: "Cancel",
            comment: "Cancel button in the Specific Dates date picker sheet on the Add/Edit Budget screen"
          )) { isPickerShown = false }
            .tint(.accentColor)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(String(
            localized: "addEditBudget.dates.picker.done",
            defaultValue: "Done",
            comment: "Done button in the Specific Dates date picker sheet on the Add/Edit Budget screen"
          )) {
            date = draft
            isPickerShown = false
          }
          .fontWeight(.semibold)
          .tint(.accentColor)
        }
      }
      .presentationDetents([.medium, .large])
    }
  }
}
