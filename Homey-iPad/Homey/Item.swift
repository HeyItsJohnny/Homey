//
//  Item.swift
//  Homey
//
//  Created by Johnny Laroco on 7/21/26.
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
