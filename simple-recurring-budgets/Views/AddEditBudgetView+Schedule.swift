import SwiftUI

// MARK: - Schedule disclosure card (recurring period types)

/// Collapsed-by-default disclosure exposing `startDate` / `endDate` for recurring
/// budgets. Most users never expand it — the resolved schedule summary (e.g.
/// "Starts May 18 · No end date") lives one tap deep so dates feel optional, not
/// like another form to fill out. Specific Dates budgets use the always-visible
/// `datesCard` in `+SpecificDates.swift` instead, since both dates are mandatory
/// for that period type.
extension AddEditBudgetView {
  var scheduleCard: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 0) {
        scheduleDisclosureRow

        if isScheduleExpanded {
          scheduleExpandedContent
            .padding(.top, 12)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
      }
      .animation(.easeInOut(duration: 0.2), value: isScheduleExpanded)
    } label: {
      sectionLabel(String(
        localized: "addEditBudget.section.schedule",
        defaultValue: "Schedule",
        comment: "Section header above the recurring-budget Schedule disclosure on the Add/Edit Budget screen"
      ))
    }
    .backgroundStyle(Color("CellBackground"))
  }

  private var scheduleDisclosureRow: some View {
    Button {
      withAnimation(.easeInOut(duration: 0.2)) {
        isScheduleExpanded.toggle()
      }
    } label: {
      HStack {
        Text(scheduleSummaryText)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.leading)
        Spacer(minLength: 8)
        Image(systemName: "chevron.down")
          .font(.caption)
          .foregroundStyle(.secondary)
          .rotationEffect(.degrees(isScheduleExpanded ? 180 : 0))
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .padding(.vertical, 4)
    .accessibilityLabel(String(
      localized: "addEditBudget.schedule.disclosure.accessibilityLabel.format",
      defaultValue: "Schedule. \(scheduleSummaryText)",
      comment: "VoiceOver label for the Schedule disclosure row; argument is the resolved summary text (e.g. 'Starts May 18 · No end date')"
    ))
    .accessibilityHint(String(
      localized: "addEditBudget.schedule.disclosure.accessibilityHint",
      defaultValue: "Tap to show or hide the start date and end date controls.",
      comment: "VoiceOver hint for the Schedule disclosure row on the Add/Edit Budget screen"
    ))
  }

  private var scheduleExpandedContent: some View {
    VStack(spacing: 12) {
      HStack(alignment: .top, spacing: 12) {
        DateColumn(
          placeholder: String(
            localized: "addEditBudget.field.date.start.recurring.placeholder",
            defaultValue: "Today",
            comment: "Placeholder shown on the start-date chip in the Add/Edit Budget Schedule disclosure for recurring period types when no value is set"
          ),
          accessibilityHint: String(
            localized: "addEditBudget.field.date.start.recurring.accessibilityHint",
            defaultValue: "Opens a calendar to pick the start date.",
            comment: "VoiceOver hint for the start-date chip in the Schedule disclosure on the Add/Edit Budget screen"
          ),
          setStateAccessibilityLabel: { date in
            String(
              localized: "addEditBudget.field.date.start.recurring.accessibilityLabel.set",
              defaultValue: "Start date, \(date.formatted(date: .abbreviated, time: .omitted))",
              comment: "VoiceOver label for the start-date chip in the Schedule disclosure when a date is set; argument is the formatted date"
            )
          },
          date: $viewModel.startDate,
          minDate: nil
        )
        DateColumn(
          placeholder: String(
            localized: "addEditBudget.field.date.end.recurring.placeholder",
            defaultValue: "No end date",
            comment: "Placeholder shown on the end-date chip in the Add/Edit Budget Schedule disclosure for recurring period types when no end date is set"
          ),
          accessibilityHint: String(
            localized: "addEditBudget.field.date.end.recurring.accessibilityHint",
            defaultValue: "Opens a calendar to pick an optional end date.",
            comment: "VoiceOver hint for the end-date chip in the Schedule disclosure on the Add/Edit Budget screen"
          ),
          setStateAccessibilityLabel: { date in
            String(
              localized: "addEditBudget.field.date.end.recurring.accessibilityLabel.set",
              defaultValue: "End date, \(date.formatted(date: .abbreviated, time: .omitted))",
              comment: "VoiceOver label for the end-date chip in the Schedule disclosure when a date is set; argument is the formatted date"
            )
          },
          date: $viewModel.endDate,
          minDate: viewModel.startDate
        )
      }
      if viewModel.endDate != nil {
        Button(String(
          localized: "addEditBudget.schedule.action.clearEndDate",
          defaultValue: "Clear end date",
          comment: "Button that clears the optional end date back to none on the Add/Edit Budget Schedule disclosure"
        )) {
          viewModel.endDate = nil
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .trailing)
      }
    }
  }

  private var scheduleSummaryText: String {
    let startPart: String
    if let startDate = viewModel.startDate {
      let formatted = startDate.formatted(date: .abbreviated, time: .omitted)
      startPart = String(
        localized: "addEditBudget.schedule.summary.start.set",
        defaultValue: "Starts \(formatted)",
        comment: "Schedule disclosure summary fragment when a start date is set; argument is the abbreviated formatted date"
      )
    } else {
      startPart = String(
        localized: "addEditBudget.schedule.summary.start.today",
        defaultValue: "Starts today",
        comment: "Schedule disclosure summary fragment when no start date has been picked yet (the budget effectively starts today)"
      )
    }
    let endPart: String
    if let endDate = viewModel.endDate {
      let formatted = endDate.formatted(date: .abbreviated, time: .omitted)
      endPart = String(
        localized: "addEditBudget.schedule.summary.end.set",
        defaultValue: "Ends \(formatted)",
        comment: "Schedule disclosure summary fragment when an end date is set; argument is the abbreviated formatted date"
      )
    } else {
      endPart = String(
        localized: "addEditBudget.schedule.summary.end.none",
        defaultValue: "No end date",
        comment: "Schedule disclosure summary fragment when no end date is set (the budget recurs indefinitely)"
      )
    }
    return "\(startPart) · \(endPart)"
  }
}
