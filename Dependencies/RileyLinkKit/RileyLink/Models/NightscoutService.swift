//
//  NightscoutService.swift
//  Loop
//
//  Created by Nate Racklyeft on 7/3/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import NightscoutKit


// Encapsulates a Nightscout site and its authentication
struct NightscoutService: ServiceAuthentication {
    var credentials: [ServiceCredential]

    let title: String = LocalizedString("Nightscout", comment: "The title of the Nightscout service")

    init(siteURL: URL?, APISecret: String?) {
        credentials = [
            ServiceCredential(
                title: LocalizedString("Site URL", comment: "The title of the nightscout site URL credential"),
                placeholder: LocalizedString("http://mysite.herokuapp.com", comment: "The placeholder text for the nightscout site URL credential"),
                isSecret: false,
                keyboardType: .URL,
                value: siteURL?.absoluteString
            ),
            ServiceCredential(
                title: LocalizedString("API Secret", comment: "The title of the nightscout API secret credential"),
                placeholder: nil,
                isSecret: false,
                keyboardType: .asciiCapable,
                value: APISecret
            )
        ]

        verify { _, _ in }
    }

    // The uploader instance, if credentials are present
    private(set) var uploader: NightscoutClient? {
        didSet {
            uploader?.errorHandler = { (error: Error, context: String) -> Void in
                print("Error \(error), while \(context)")
            }
        }
    }

    var siteURL: URL? {
        if let URLString = credentials[0].value {
            return URL(string: URLString)
        }

        return nil
    }

    var APISecret: String? {
        return credentials[1].value
    }

    private(set) var isAuthorized: Bool = false

    mutating func verify(_ completion: @escaping (_ success: Bool, _ error: Error?) -> Void) {
        
        guard let siteURL = siteURL, let APISecret = APISecret else {
            completion(false, nil)
            return
        }
        self.uploader = NightscoutClient(siteURL: siteURL, apiSecret: APISecret)
        
        self.uploader?.checkAuth({ (error) in
            if let error = error {
                // self.isAuthorized = false
                completion(false, error)
            } else {
                // self.isAuthorized = true
                completion(true, nil)
            }
        })
    }

    mutating func reset() {
        credentials[0].value = nil
        credentials[1].value = nil
        isAuthorized = false
        uploader = nil
    }
}
