import SwiftUI

/// Pushable screen for changing the global week-start day from inside a navigation stack
/// (e.g. the Add/Edit Budget form) without losing in-progress work (F-5.01).
///
/// Writes the same global `AppSettings.weekStartDay` as Settings, behind the same cascade
/// warning (`WeekStartConfirmation` + shared `settings.weekStart.alert.*` strings), so it
/// reads as app-wide rather than a per-budget control.
struct WeekStartPickerScreen: View {
  @Environment(AppSettings.self) private var settings
  @Environment(\.analytics) private var analytics

  /// Holds the pending selection until the cascade alert confirms.
  @State private var confirmation = WeekStartConfirmation()

  var body: some View {
    List {
      // Scope banner above the control: the main signal that this setting is app-wide.
      Section {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
          // Accent tint instead of the symbol's default multicolor orange, to stay on
          // the calm palette. Same font as the text so it baseline-aligns with the first
          // line and scales with Dynamic Type.
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
          weekdayRow(day)
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
        set: {
          if !$0 {
            confirmation.cancel()
          }
        }
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

  @ViewBuilder
  private func weekdayRow(_ day: Weekday) -> some View {
    let isSelected = day == settings.weekStartDay
    Button {
      confirmation.select(day, current: settings.weekStartDay)
    } label: {
      HStack {
        Text(weekdayName(day))
          .foregroundStyle(.primary)
        Spacer()
        if isSelected {
          // Decorative: the .isSelected trait below conveys selection to VoiceOver.
          Image(systemName: "checkmark")
            .foregroundStyle(Color.accentColor)
            .accessibilityHidden(true)
        }
      }
    }
    .accessibilityIdentifier("weekStart.day.\(day.rawValue)")
    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    .listRowBackground(Color("CellBackground"))
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

  #Preview("Week Start Picker — xxxLarge") {
    NavigationStack {
      WeekStartPickerScreen()
        .environment(AppSettings())
    }
    .dynamicTypeSize(.xxxLarge)
  }
#endif
