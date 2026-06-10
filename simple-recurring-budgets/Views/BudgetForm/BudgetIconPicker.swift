import SwiftUI

// MARK: - Budget icon picker

/// Curated icon picker presented as a sheet for choosing a Budget's optional icon
/// (F-4.03). The icon is a single emoji chosen from a curated set; selecting one
/// writes it back through `selection` and dismisses, and "Remove" clears it. This
/// component is the **master source** for which emoji the app offers — feature
/// docs intentionally do not enumerate the set.
struct BudgetIconPicker: View {
  @Binding var selection: String?
  @Environment(\.dismiss) private var dismiss

  /// Curated, budget-relevant emoji, loosely grouped by spending category. Chosen
  /// to cover the PRD personas' recurring categories — daily food & coffee, weekly
  /// groceries, clothes/beauty, transit, little luxuries, kids' treats, pets, home,
  /// health, hobbies, travel (see docs/main-prd.md §5 and docs/ux-design-brief.md).
  /// A short tongue-in-cheek set is tacked on at the end for less-buttoned-up
  /// budgets. Kept to a curated list rather than the full Unicode catalog. Entries
  /// MUST stay unique (the grid keys `ForEach` on the emoji itself). This is the
  /// master source for the budget icon set (F-4.03); exposed `static` for tests.
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
            .foregroundStyle(.primary)
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
