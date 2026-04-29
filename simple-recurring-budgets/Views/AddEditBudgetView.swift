//
//  AddEditBudgetView.swift
//  simple-recurring-budgets
//

import SwiftUI
import SwiftData

struct AddEditBudgetView: View {
    @State var viewModel: AddEditBudgetViewModel
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var showCurrencyPicker = false
    @FocusState private var isNameFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    nameCard
                    allocationCard
                    periodCard
                    carryOverCard
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .onAppear {
                if !viewModel.isEditing {
                    isNameFocused = true
                }
            }
            .navigationTitle(viewModel.isEditing
                ? String(
                    localized: "addEditBudget.title.edit",
                    defaultValue: "Edit Budget",
                    comment: "Navigation bar title when editing an existing budget"
                )
                : String(
                    localized: "addEditBudget.title.add",
                    defaultValue: "New Budget",
                    comment: "Navigation bar title when creating a new budget"
                )
            )
            .navigationBarTitleDisplayMode(.inline)
            .appBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(
                        localized: "addEditBudget.action.cancel",
                        defaultValue: "Cancel",
                        comment: "Button that dismisses the Add/Edit Budget sheet without saving"
                    )) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(
                        localized: "addEditBudget.action.save",
                        defaultValue: "Save",
                        comment: "Button that saves the budget and dismisses the Add/Edit Budget sheet"
                    )) {
                        viewModel.save(context: context)
                        dismiss()
                    }
                    .disabled(!viewModel.canSave)
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showCurrencyPicker) {
                CurrencyPickerView(selection: $viewModel.currencyCode)
            }
        }
    }

    // MARK: - Cards

    private var nameCard: some View {
        GroupBox {
            TextField(
                String(
                    localized: "addEditBudget.field.name.placeholder",
                    defaultValue: "Budget",
                    comment: "Placeholder text for the budget name field"
                ),
                text: $viewModel.name
            )
            .font(.body)
            .focused($isNameFocused)
            .accessibilityLabel(String(
                localized: "addEditBudget.field.name.accessibilityLabel",
                defaultValue: "Budget name",
                comment: "VoiceOver label for the budget name text field"
            ))
        } label: {
            sectionLabel(String(
                localized: "addEditBudget.section.name",
                defaultValue: "Name",
                comment: "Section header above the budget name field"
            ))
        }
        .backgroundStyle(Color("CellBackground"))
    }

    private var allocationCard: some View {
        GroupBox {
            HStack(alignment: .center, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(currencyPrefix)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField(
                        String(
                            localized: "addEditBudget.field.allocation.placeholder",
                            defaultValue: "0",
                            comment: "Placeholder in the allocation amount field when no value is entered"
                        ),
                        value: $viewModel.allocation,
                        format: OptionalDecimalFormatStyle()
                    )
                    .keyboardType(.decimalPad)
                    .font(.title2.weight(.semibold).monospacedDigit())
                    .accessibilityLabel(
                        String(
                            localized: "addEditBudget.field.allocation.accessibilityLabel",
                            defaultValue: "Allocation amount, \((viewModel.allocation ?? 0).formatted(currencyCode: viewModel.currencyCode, display: settings.currencyDisplay))",
                            comment: "VoiceOver label for the allocation field; argument is the formatted monetary amount including currency"
                        )
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    showCurrencyPicker = true
                } label: {
                    HStack(spacing: 4) {
                        Text(viewModel.currencyCode)
                            .font(.callout.weight(.medium))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.secondary.opacity(0.12)))
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(
                    localized: "addEditBudget.field.currency.accessibilityLabel",
                    defaultValue: "Currency, \(viewModel.currencyCode)",
                    comment: "VoiceOver label for the currency selection pill showing the current ISO code"
                ))
                .accessibilityHint(String(
                    localized: "addEditBudget.field.currency.accessibilityHint",
                    defaultValue: "Opens currency picker",
                    comment: "VoiceOver hint for the currency selection pill"
                ))
            }
        } label: {
            sectionLabel(String(
                localized: "addEditBudget.section.allocation",
                defaultValue: "Allocation",
                comment: "Section header above the allocation amount and currency fields"
            ))
        }
        .backgroundStyle(Color("CellBackground"))
    }

    private var periodCard: some View {
        GroupBox {
            let columns = [GridItem(.flexible()), GridItem(.flexible())]
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(BudgetPeriod.allCases, id: \.self) { p in
                    periodChip(p)
                }
            }
        } label: {
            sectionLabel(String(
                localized: "addEditBudget.section.period",
                defaultValue: "Period",
                comment: "Section header above the budget period chip grid"
            ))
        }
        .backgroundStyle(Color("CellBackground"))
    }

    private var carryOverCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 0) {
                Toggle(
                    String(
                        localized: "addEditBudget.section.carryOver",
                        defaultValue: "Carry-Over",
                        comment: "Toggle label and section header for the carry-over setting on the Add/Edit Budget screen"
                    ),
                    isOn: $viewModel.isCarryOverEnabled
                )
                .tint(.accentColor)
                .accessibilityHint(String(
                    localized: "addEditBudget.toggle.carryOver.accessibilityHint",
                    defaultValue: "When on, unspent or overspent amounts carry forward across periods",
                    comment: "VoiceOver hint for the carry-over toggle on the Add/Edit Budget screen"
                ))

                Text(String(
                    localized: "addEditBudget.note.carryOver",
                    defaultValue: "Accumulates unspent or overspent amounts over time.",
                    comment: "Caption below the carry-over toggle explaining what carry-over does"
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
            }
            .animation(.easeInOut(duration: 0.2), value: viewModel.isCarryOverEnabled)
        } label: {
            sectionLabel(String(
                localized: "addEditBudget.section.carryOver",
                defaultValue: "Carry-Over",
                comment: "Toggle label and section header for the carry-over setting on the Add/Edit Budget screen"
            ))
        }
        .backgroundStyle(Color("CellBackground"))
    }

    // MARK: - Period chip

    private func periodChip(_ p: BudgetPeriod) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                viewModel.period = p
            }
        } label: {
            Text(p.listLabel)
                .font(.subheadline)
                .fontWeight(viewModel.period == p ? .semibold : .regular)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(viewModel.period == p ? Color.accentColor : Color.secondary.opacity(0.1))
                )
                .foregroundStyle(viewModel.period == p ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(
            localized: "addEditBudget.chip.period.accessibilityLabel",
            defaultValue: "\(p.listLabel) period",
            comment: "VoiceOver label for a period selection chip; argument is the period name (Daily, Weekly, etc.)"
        ))
        .accessibilityAddTraits(viewModel.period == p ? .isSelected : [])
    }

    // MARK: - Helpers

    private var currencyPrefix: String {
        let symbol = currencySymbol(for: viewModel.currencyCode)
        switch settings.currencyDisplay {
        case .symbol:        return symbol
        case .code:          return viewModel.currencyCode
        case .codeAndSymbol: return "\(viewModel.currencyCode) \(symbol)"
        }
    }

    private func currencySymbol(for code: String) -> String {
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.currencyCode = code
        return fmt.currencySymbol
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }
}

// MARK: - Allocation format style

private struct OptionalDecimalFormatStyle: ParseableFormatStyle {
    typealias FormatInput = Decimal?
    typealias FormatOutput = String

    func format(_ value: Decimal?) -> String {
        guard let value else { return "" }
        return value.formatted(.number.precision(.fractionLength(0...2)))
    }

    var parseStrategy: OptionalDecimalParseStrategy { OptionalDecimalParseStrategy() }
}

private struct OptionalDecimalParseStrategy: ParseStrategy {
    typealias ParseInput = String
    typealias ParseOutput = Decimal?

    func parse(_ value: String) throws -> Decimal? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        guard let decimal = Decimal(string: trimmed, locale: .current) else {
            throw CocoaError(.formatting)
        }
        return decimal
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Add — Light") {
    AddEditBudgetView(viewModel: AddEditBudgetViewModel(settings: AppSettings()))
        .modelContainer(PreviewContainer.make())
        .environment(AppSettings())
}

#Preview("Add — Dark") {
    AddEditBudgetView(viewModel: AddEditBudgetViewModel(settings: AppSettings()))
        .modelContainer(PreviewContainer.make())
        .environment(AppSettings())
        .preferredColorScheme(.dark)
}

#Preview("Edit — Light") {
    let budget = DebugData.dailyDefault()
    return AddEditBudgetView(viewModel: AddEditBudgetViewModel(editing: budget))
        .modelContainer(PreviewContainer.make())
        .environment(AppSettings())
}

#Preview("Edit — Dark") {
    let budget = DebugData.monthlyDefault()
    return AddEditBudgetView(viewModel: AddEditBudgetViewModel(editing: budget))
        .modelContainer(PreviewContainer.make())
        .environment(AppSettings())
        .preferredColorScheme(.dark)
}

#Preview("xxxLarge Type") {
    let budget = DebugData.weeklyDefault()
    return AddEditBudgetView(viewModel: AddEditBudgetViewModel(editing: budget))
        .modelContainer(PreviewContainer.make())
        .environment(AppSettings())
        .dynamicTypeSize(.xxxLarge)
}

#Preview("Empty — Save disabled") {
    let vm = AddEditBudgetViewModel(settings: AppSettings())
    vm.name = ""
    vm.allocation = nil
    return AddEditBudgetView(viewModel: vm)
        .modelContainer(PreviewContainer.make())
        .environment(AppSettings())
}
#endif
