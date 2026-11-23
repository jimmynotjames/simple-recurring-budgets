import SwiftUI

// MARK: - Budget icon picker

/// Sheet for choosing a budget's optional icon, a single emoji from a curated set;
/// picking writes `selection` and dismisses, "Remove" clears it. Master source for the
/// offered emoji; feature docs deliberately don't enumerate them.
struct BudgetIconPicker: View {
  @Binding var selection: String?
  @Environment(\.dismiss) private var dismiss

  /// Curated emoji grouped by spending category, covering the PRD personas' recurring
  /// categories (docs/main-prd.md §5), plus a short tongue-in-cheek set at the end.
  /// Entries MUST stay unique (`ForEach` keys on the emoji). `static` for tests.
  static let curatedIcons: [String] = [
    // Food & dining
    "🍴", "🍔", "🍕", "🍣", "🍜", "🥗", "🌮", "🍱", "🥡",
    // Coffee, tea & treats
    "☕", "🧋", "🍵", "🍦", "🍩", "🧁", "🍫", "🍪",
    // Drinks
    "🍺", "🍷",
    // Groceries & produce
    "🛒", "🥦", "🥕", "🍎", "🥖", "🥚",
    // Shopping & style
    "🛍️", "👕", "👗", "👟", "👠", "👜", "💄", "💅", "🕶️",
    // Transit & commute
    "🚗", "⛽", "🚌", "🚆", "🚲", "🛵",
    // Home & household
    "🏠", "🛋️", "🧺", "🧻", "🔧", "🛏️",
    // Health & wellness — incl. yoga/meditation, hiking, boating
    "💊", "🏥", "🧘", "🪷", "🏋️", "💪", "🥾", "⛰️", "🏕️", "⛵", "🚣", "🛶",
    // Travel
    "✈️", "🧳", "🏖️", "🏝️", "🗺️", "🏨", "🛳️", "🏞️", "🎡", "🧭", "📸",
    // Fun, hobbies & entertainment
    "🎬", "🎮", "🎵", "📚", "🎨", "🎟️", "🎲", "🎸",
    // Kids, family & pets
    "🧸", "👶", "🐶", "🐱", "🐾",
    // Gifts & money
    "🎁", "💳", "💰", "📦",
    // Cheeky / just for fun
    "🚬", "🍑", "💦", "🌶️", "🍒", "🍌", "💋", "🔥", "😏", "🍆", "🔗", "🪢", "🎈",
  ]

  private let columns = [GridItem(.adaptive(minimum: 56), spacing: 12)]

  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVGrid(columns: columns, spacing: 12) {
          ForEach(Self.curatedIcons, id: \.self) { item in
            Button {
              selection = item
              dismiss()
            } label: {
              Text(verbatim: item)
                .font(.largeTitle)
                .lineLimit(1)
                .frame(width: 56, height: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .overlay {
              RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                  selection == item ? Color.accentColor : Color.clear,
                  lineWidth: 2
                )
            }
            .accessibilityLabel(Text(verbatim: item))
            .accessibilityAddTraits(selection == item ? [.isSelected] : [])
          }
        }
        .padding()
      }
      .navigationTitle(String(
        localized: "addEditBudget.iconPicker.title",
        defaultValue: "Optional Icon",
        comment: "Title of the optional budget icon picker sheet on the Add/Edit Budget screen"
      ))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(String(
            localized: "addEditBudget.iconPicker.cancel",
            defaultValue: "Cancel",
            comment: "Button that dismisses the budget icon picker without changing the selection"
          )) { dismiss() }
            .tint(.accentColor)
        }
        if selection != nil {
          ToolbarItem(placement: .topBarTrailing) {
            Button(String(
              localized: "addEditBudget.iconPicker.remove",
              defaultValue: "Remove",
              comment: "Button on the budget icon picker that clears the budget's chosen icon"
            )) {
              selection = nil
              dismiss()
            }
            .tint(.accentColor)
          }
        }
      }
    }
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
  }
}

// MARK: - Preview

#if DEBUG
  /// Hosts `BudgetIconPicker` in a sheet so the preview lands directly on the grid.
  private struct BudgetIconPickerPreviewHost: View {
    @State var selection: String?
    @State private var showing = true
    var colorScheme: ColorScheme? = nil

    init(initial: String?, colorScheme: ColorScheme? = nil) {
      _selection = State(initialValue: initial)
      self.colorScheme = colorScheme
    }

    var body: some View {
      Color.clear
        .sheet(isPresented: $showing) {
          BudgetIconPicker(selection: $selection)
            .preferredColorScheme(colorScheme)
        }
    }
  }

  #Preview("Budget icon picker — Light") {
    BudgetIconPickerPreviewHost(initial: nil)
  }

  #Preview("Budget icon picker — Dark") {
    BudgetIconPickerPreviewHost(initial: "☕", colorScheme: .dark)
  }
#endif
