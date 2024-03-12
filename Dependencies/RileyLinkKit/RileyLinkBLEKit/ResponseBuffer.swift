//
//  ResponseBuffer.swift
//  RileyLinkBLEKit
//
//  Copyright © 2018 Pete Schwamb. All rights reserved.
//


/// Represents a data buffer containing one or more responses
struct ResponseBuffer<R: Response> {
    let endMarker: UInt8
    private var data = Data()

    init(endMarker: UInt8) {
        self.endMarker = endMarker
    }

    mutating func append(_ other: Data) {
        data.append(other)
    }

    var responses: [R] {
        let segments = data.split(separator: endMarker, omittingEmptySubsequences: false)

        // If we haven't received at least one endMarker, we don't have a response.
        guard segments.count > 1 else {
            return []
        }

        return segments.compactMap { R(legacyData: $0) }
    }
}
