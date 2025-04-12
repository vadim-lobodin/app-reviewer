//
//  Item.swift
//  App Reviewer
//
//  Created by Vadim.Lobodin on 12.04.25.
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
