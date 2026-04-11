//
//  Item.swift
//  simple-recurring-budgets
//
//  Created by Jimmy Ho on 4/10/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    /// CloudKit requires stored properties to be optional or have a default at the property site.
    var timestamp: Date = Date()

    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
