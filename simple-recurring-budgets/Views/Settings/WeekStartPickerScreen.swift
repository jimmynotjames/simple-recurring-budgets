import SwiftUI

/// Focused, pushable screen for changing the global week-start day from *inside* a
/// navigation stack (e.g. the Add/Edit Budget form) without leaving the current flow.
/// Pushing it onto the host's `NavigationStack` keeps any in-progress work alive
/// underneath, and tapping back returns the user where they were with the new
/// week-start reflected.
///
/// It writes the same global `AppSettings.weekStartDay` the Settings screen does, gated
/// by the same cascade-warning confirmation (`WeekStartConfirmation` + the shared
/// `settings.weekStart.alert.*` strings), so it stays honest about the setting's
/// app-wide scope rather than reading as a per-budget control.
struct WeekStartPickerScreen: View {
  @Environment(AppSettings.self) private var settings
  @Environment(\.analytics) private var analytics

  /// Holds the pending selection until the user confirms in the cascade alert (F-5.01).
  @State private var confirmation = WeekStartConfirmation()

  var body: some View {
    List {
      // Scope banner, placed above the control so it's seen before the user acts —
      // the primary signal that this setting is app-wide.
      Section {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
          // Warning-triangle shape for "heads up, this is broad", but tinted with the
          // app accent instead of the default multicolor orange to stay on Wren's calm
          // palette (foregroundStyle overrides the symbol's built-in color).
          // Matching the text font lets the symbol baseline-align with the first line
          // of wrapped text and scale with Dynamic Type.
          Image(systemName: "exclamationmark.triangle.fill")
            .font(.subheadline)
            .foregroundStyle(Color.accentColor)
            .accessibilityHidden(true)
          Text(String(
            localized: "weekStartPicker.scopeNote",
            defaultValue: "App-wide setting. Changes here will update all weekly budgets.",
            comment: """
            Banner at the top of the focused week-start picker. Makes clear the setting \
            is global (app-wide), affecting all weekly budgets — not scoped to the \
            budget the user navigated from.
            """
          ))
          .font(.subheadline)
          .foregroundStyle(.primary)
        }
        .listRowBackground(Color("CellBackground"))
      }

      Section {
        ForEach(Weekday.allCases) { day in
          Button {
            confirmation.select(day, current: settings.weekStartDay)
          } label: {
            HStack {
              Text(weekdayName(day))
                .foregroundStyle(.primary)
              Spacer()
              if day == settings.weekStartDay {
                Image(systemName: "checkmark")
                  .foregroundStyle(Color.accentColor)
              }
            }
          }
          .listRowBackground(Color("CellBackground"))
        }
      } header: {
        Text(String(
          localized: "settings.weekStart.label",
          defaultValue: "Week Starts On",
          comment: "Label for the week-start day picker in Settings"
        ))
        .foregroundStyle(.primary)
      }
    }
    .navigationTitle(String(
      localized: "weekStartPicker.navTitle",
      defaultValue: "Start of Week",
      comment: "Navigation title of the focused week-start picker screen"
    ))
    .navigationBarTitleDisplayMode(.inline)
    .appBackground()
    .alert(
      String(
        localized: "settings.weekStart.alert.title",
        defaultValue: "Change Start of Week?",
        comment: "Title of the confirmation alert shown before applying a week-start day change"
      ),
      isPresented: Binding(
        get: { confirmation.isPresenting },
        set: { if !$0 { confirmation.cancel() } }
      )
    ) {
      Button(String(
        localized: "settings.weekStart.alert.confirm",
        defaultValue: "Change",
        comment: "Confirm button in the week-start day change alert"
      )) {
        if let day = confirmation.confirm() {
          let oldDay = settings.weekStartDay
          settings.weekStartDay = day
          analytics.track(
            AnalyticsEvent.settingChanged,
            properties: [
              AnalyticsProperty.settingName: "week_start_day",
              AnalyticsProperty.newValue: day.analyticsValue,
              AnalyticsProperty.oldValue: oldDay.analyticsValue,
            ]
          )
        }
      }
      Button(String(
        localized: "settings.weekStart.alert.cancel",
        defaultValue: "Cancel",
        comment: "Cancel button in the week-start day change alert"
      ), role: .cancel) {
        confirmation.cancel()
      }
    } message: {
      if let day = confirmation.pending {
        Text(String(
          localized: "settings.weekStart.alert.message",
          defaultValue: "Changing to \(weekdayName(day)) will also affect existing weekly budgets and recalculate past weeks.",
          comment: "Alert body for the week-start day change; argument is the name of the newly selected weekday. Warns that the change also re-aligns existing weekly budgets and recalculates their past weeks."
        ))
      }
    }
  }

  private func weekdayName(_ weekday: Weekday) -> String {
    Calendar.current.standaloneWeekdaySymbols[weekday.rawValue - 1]
  }
}

#if DEBUG
  #Preview("Week Start Picker") {
    NavigationStack {
      WeekStartPickerScreen()
        .environment(AppSettings())
    }
  }
#endif
