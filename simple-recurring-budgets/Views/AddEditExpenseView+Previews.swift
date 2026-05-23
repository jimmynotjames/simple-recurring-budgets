import SwiftData
import SwiftUI

// MARK: - Previews

#if DEBUG
  #Preview("Add — Light") {
    NavigationStack {
      AddEditExpenseView(viewModel: AddEditExpenseViewModel(adding: DebugData.dailyDefault()))
    }
    .modelContainer(PreviewContainer.make())
    .environment(AppSettings())
  }

  #Preview("Add — Dark") {
    NavigationStack {
      AddEditExpenseView(viewModel: AddEditExpenseViewModel(adding: DebugData.weeklyDefault()))
    }
    .modelContainer(PreviewContainer.make())
    .environment(AppSettings())
    .preferredColorScheme(.dark)
  }

  #Preview("Existing expense — Light") {
    let budget = DebugData.dailyDefault()
    return NavigationStack {
      AddEditExpenseView(
        viewModel: AddEditExpenseViewModel(editing: budget.expenseItems[0])
      )
    }
    .modelContainer(PreviewContainer.make())
    .environment(AppSettings())
  }

  #Preview("Existing expense — Dark") {
    let budget = DebugData.monthlyDefault()
    return NavigationStack {
      AddEditExpenseView(
        viewModel: AddEditExpenseViewModel(editing: budget.expenseItems[0])
      )
    }
    .modelContainer(PreviewContainer.make())
    .environment(AppSettings())
    .preferredColorScheme(.dark)
  }

  #Preview("xxxLarge Type") {
    NavigationStack {
      AddEditExpenseView(viewModel: AddEditExpenseViewModel(adding: DebugData.dailyDefault()))
    }
    .modelContainer(PreviewContainer.make())
    .environment(AppSettings())
    .dynamicTypeSize(.xxxLarge)
  }

  #Preview("Empty — Save disabled") {
    let vm = AddEditExpenseViewModel(adding: DebugData.dailyDefault())
    vm.amount = nil
    return NavigationStack {
      AddEditExpenseView(viewModel: vm)
    }
    .modelContainer(PreviewContainer.make())
    .environment(AppSettings())
  }

  #Preview("Add — Pre-start budget") {
    NavigationStack {
      AddEditExpenseView(viewModel: AddEditExpenseViewModel(adding: DebugData.dailyPreStart()))
    }
    .modelContainer(PreviewContainer.make())
    .environment(AppSettings())
  }

  #Preview("Add — Post-end budget") {
    NavigationStack {
      AddEditExpenseView(viewModel: AddEditExpenseViewModel(adding: DebugData.weeklyPostEnd()))
    }
    .modelContainer(PreviewContainer.make())
    .environment(AppSettings())
  }
#endif
