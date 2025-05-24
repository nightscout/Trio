//
// Trio
// MD5.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-01-01.
// Most contributions by Ivan Valkou.
//
// Documentation available under: https://triodocs.org/

import CryptoKit
import Foundation

extension Data {
    var md5String: String {
        let digest = Insecure.MD5.hash(data: self)
        return digest.map {
            String(format: "%02hhx", $0)
        }.joined()
    }
}

extension String {
    var md5String: String {
        (data(using: .utf8) ?? Data()).md5String
    }
}
