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
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
