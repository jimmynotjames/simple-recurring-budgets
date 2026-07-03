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

/// Side-by-side date chip + sheet picker used by the Add/Edit Budget Dates card.
///
/// Renders as a full-width rounded-rect chip (matching the unselected period chip style)
/// in the empty state with a localized placeholder ("Choose start date" / "Choose end date").
/// Once a date is set, the chip shows the locale-aware abbreviated form (e.g. "May 18, 2026").
/// Tapping the chip presents a sheet containing a `.graphical` `DatePicker`; Cancel discards,
/// Done assigns. Single-tap UX: tap → sheet → pick → Done.
///
/// **Not a reusable component.** The `placeholder`, `accessibilityHint`, and
/// `setStateAccessibilityLabel` closure are all wired to localization keys specific to
/// the Add/Edit Budget Dates card. If a second site needs a similar chip+picker,
/// extract a reusable shell first rather than reusing this struct as-is.
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
      // Retire any keyboard left up by name/allocation editing before the picker sheet
      // covers it. Without this, iOS restores the prior first responder when the sheet
      // is dismissed and the keyboard springs back up over the form.
      dismissKeyboard()
      // Floor the draft at minDate so it can never land below the picker's allowed
      // range. The VM's snap-forward keeps `date >= minDate` in normal flow; this
      // guard covers regressions and any future caller that wires `minDate` directly.
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
