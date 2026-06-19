import SwiftData
import SwiftUI

// MARK: - AddEditBudgetView previews

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

  #Preview("Add — Weekly (note + link)") {
    let vm = AddEditBudgetViewModel(settings: AppSettings())
    vm.period = .weekly
    return AddEditBudgetView(viewModel: vm)
      .modelContainer(PreviewContainer.make())
      .environment(AppSettings())
      .environment(Router())
  }

  #Preview("Edit — Biweekly (note + schedule)") {
    // Biweekly edit: the explanatory note shows under the period chips and the
    // Schedule disclosure auto-expands so the start date (the cycle anchor) is visible.
    let budget = DebugData.biweeklyDefault()
    return AddEditBudgetView(viewModel: AddEditBudgetViewModel(editing: budget))
      .modelContainer(PreviewContainer.make())
      .environment(AppSettings())
      .environment(Router())
  }

  #Preview("Edit — Orphaning start date") {
    // weeklyDefault has expenses at day 0, -7, -21, -35.
    // Moving startDate to 20 days ago orphans the day-21 and day-35 expenses (count = 2).
    let budget = DebugData.weeklyDefault()
    let vm = AddEditBudgetViewModel(editing: budget)
    vm.startDate = Calendar.current.date(byAdding: .day, value: -20, to: Calendar.current.startOfDay(for: Date()))
    return AddEditBudgetView(viewModel: vm)
      .modelContainer(PreviewContainer.make())
      .environment(AppSettings())
      .environment(Router())
  }
#endif
