//
//  LocalizedString.swift
//  LoopKit
//
//  Created by Retina15 on 8/6/18.
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Foundation

// really needs to be a class to compile 
// swiftlint:disable:next convenience_type
internal class FrameworkBundle {
    static let main = Bundle(for: FrameworkBundle.self)
}

func LocalizedString(_ key: String, tableName: String? = nil, value: String? = nil, comment: String) -> String {
    if let value {
        return NSLocalizedString(key, tableName: tableName, bundle: FrameworkBundle.main, value: value, comment: comment)
    } else {
        return NSLocalizedString(key, tableName: tableName, bundle: FrameworkBundle.main, comment: comment)
    }
}
/*
extension DefaultStringInterpolation {
    mutating func appendInterpolation<T>(_ optional: T?) {
        appendInterpolation(String(describing: optional))
    }
}*/
