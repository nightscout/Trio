//
//  CollectionExtensions.swift
//  MiaomiaoClientUI
//
//  Created by LoopKit Authors on 26/03/2019.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var addedDict = [Element: Bool]()

        return filter {
            addedDict.updateValue(true, forKey: $0) == nil
        }
    }

    func removingDuplicates<T: Hashable>(byKey key: (Element) -> T) -> [Element] {
         var result = [Element]()
         var seen = Set<T>()
         for value in self {
             if seen.insert(key(value)).inserted {
                 result.append(value)
             }
         }
         return result
     }

    mutating func removeDuplicates() {
        self = self.removingDuplicates()
    }
}
