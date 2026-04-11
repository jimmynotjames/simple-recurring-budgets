//
//  ExpenseItem.swift
//  simple-recurring-budgets
//
//  Created by Jimmy Ho on 4/11/26.
//

import Foundation
import SwiftData

/// A single transaction linked to a `Budget`.
///
/// `amount` is signed: positive values represent an expense, negative values represent
/// adding funds (F-6.01). Use `isAddFunds` and `displayAmount` for display logic.
@Model
final class ExpenseItem {
    var id: UUID = UUID()
    /// Signed: positive = expense, negative = add funds (F-6.01).
    var amount: Decimal = 0
    var name: String? = nil
    var date: Date = Date()
    var createdAt: Date = Date()
    var lastModified: Date = Date()
    /// e.g. "Cash", "Credit Card" (F-6.02). Stored for future use.
    var expenseType: String? = nil

    var budget: Budget?

    /// `true` when this transaction represents adding funds (negative `amount`).
    var isAddFunds: Bool { amount < 0 }

    /// The absolute value of `amount` for display purposes.
    var displayAmount: Decimal { amount < 0 ? -amount : amount }

    init(
        amount: Decimal = 0,
        name: String? = nil,
        date: Date = Date(),
        expenseType: String? = nil
    ) {
        self.amount = amount
        self.name = name
        self.date = date
        self.expenseType = expenseType
    }
}
