import SwiftUI

/// WORKSHOP — Specific Dates UI bits.
/// Strings inline (not localized); no accessibility wiring; dates are not persisted
/// by AddEditBudgetViewModel.save(...). Will be wired up in a follow-up change.
extension AddEditBudgetView {
  var isSpecificDates: Bool {
    viewModel.period == .specificDates
  }

  var datesValid: Bool {
    guard isSpecificDates else { return true }
    guard let start = startDate, let end = endDate else { return false }
    return start <= end
  }

  var canSave: Bool {
    viewModel.canSave && datesValid
  }

  var datesCard: some View {
    GroupBox {
      HStack(alignment: .top, spacing: 12) {
        DateColumn(placeholder: "Choose start date", date: $startDate, minDate: nil)
        DateColumn(placeholder: "Choose end date", date: $endDate, minDate: startDate)
      }
      .padding(.top, 4)
      .animation(.easeInOut(duration: 0.15), value: startDate)
      .animation(.easeInOut(duration: 0.15), value: endDate)
    } label: {
      sectionLabel("Dates")
    }
    .backgroundStyle(Color("CellBackground"))
  }
}

/// Workshop — single tap on the chip opens a sheet with a graphical DatePicker.
/// Replaces the previous two-tap flow where the empty-state Button consumed the
/// first tap (just to assign a date) and the `.compact` DatePicker swallowed the
/// second tap to open the calendar.
struct DateColumn: View {
  let placeholder: String
  @Binding var date: Date?
  let minDate: Date?

  @State private var isPickerShown = false
  @State private var draft: Date = .init()

  var body: some View {
    Button {
      draft = date ?? minDate ?? Date()
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
        .foregroundStyle(Color.primary)
    }
    .buttonStyle(.plain)
    .frame(maxWidth: .infinity, alignment: .leading)
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

  private var pickerSheet: some View {
    NavigationStack {
      DatePicker(
        "",
        selection: $draft,
        in: (minDate ?? .distantPast) ... Date.distantFuture,
        displayedComponents: .date
      )
      .datePickerStyle(.graphical)
      .labelsHidden()
      .padding()
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { isPickerShown = false }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") {
            date = draft
            isPickerShown = false
          }
          .fontWeight(.semibold)
        }
      }
      .presentationDetents([.medium, .large])
    }
  }
}
