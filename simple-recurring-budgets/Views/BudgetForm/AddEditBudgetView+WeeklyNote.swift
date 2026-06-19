import SwiftUI

extension AddEditBudgetView {
  /// Disclosure shown under the period grid when Weekly is selected: states the global
  /// week-start day all weekly budgets share, with a link that pushes the focused Start
  /// of Week picker onto the form's own NavigationStack (the in-progress draft stays
  /// alive underneath; on return the caption re-reads `settings.weekStartDay` live).
  var weeklyNote: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(String(
        localized: "addEditBudget.note.weekly",
        defaultValue: "All weekly budgets start on \(weekStartDayName).",
        comment: """
        Caption below the period chip grid when Weekly is selected. States the global \
        week-start day that all weekly budgets share. The interpolated value is the \
        localized weekday name, e.g. Sunday.
        """
      ))
      .font(.caption)
      .foregroundStyle(.readableSecondary)

      NavigationLink {
        WeekStartPickerScreen()
      } label: {
        Text(String(
          localized: "addEditBudget.note.weekly.changeLink",
          defaultValue: "Change start of week",
          comment: """
          Quiet inline link below the weekly note that opens the screen where the \
          global week-start day can be changed.
          """
        ))
        .font(.caption)
        .foregroundStyle(Color.accentColor)
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("addEditBudget.changeStartOfWeek")
      .accessibilityHint(String(
        localized: "addEditBudget.note.weekly.changeLink.accessibilityHint",
        defaultValue: "Opens the app-wide start-of-week setting",
        comment: "VoiceOver hint for the Change start of week link below the weekly note; clarifies the destination changes an app-wide setting."
      ))
    }
    .padding(.top, 4)
    .transition(.opacity.combined(with: .move(edge: .top)))
  }

  /// Localized name of the global week-start day (e.g. "Sunday"). Mirrors
  /// `SettingsView.weekdayName(_:)`; `Weekday` is 1-based (sunday = 1), the symbols
  /// array is 0-based, hence `rawValue - 1`.
  var weekStartDayName: String {
    Calendar.current.standaloneWeekdaySymbols[settings.weekStartDay.rawValue - 1]
  }
}
