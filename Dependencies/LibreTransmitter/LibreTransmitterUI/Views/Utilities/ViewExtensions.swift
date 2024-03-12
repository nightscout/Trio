//
//  ViewExtensions.swift
//  LibreTransmitterUI
//
//  Created by LoopKit Authors on 03/07/2021.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LocalAuthentication

extension View {
    func hideKeyboardPreIos16() {
        if #unavailable(iOS 16.0) {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }
}

struct LeadingImage: View {
    
    var image: UIImage
    
    static let compactScreenImageHeight: CGFloat = 70
    static let regularScreenImageHeight: CGFloat = 150

    @Environment(\.verticalSizeClass) var verticalSizeClass
    
    init(_ image: UIImage) {
        self.image = image
    }
    
    var body: some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: ContentMode.fit)
            .frame(height: self.verticalSizeClass == .compact ? LeadingImage.compactScreenImageHeight : LeadingImage.regularScreenImageHeight)
            .padding(.vertical, self.verticalSizeClass == .compact ? 0 : nil)
            
    }
}

extension View {
    func getLeadingImage() -> some View {
        LeadingImage(UIImage(named: "libresensor200", in: Bundle.current, compatibleWith: nil)!)
    }
    
    func authenticate(success authSuccess: @escaping (Bool) -> Void) {
        let context = LAContext()
        var error: NSError?
        
        // check whether authentication is possible
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            // it's possible, so go ahead and use it
            let reason = "We need to unlock your data."

            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) {  success, _  in
                authSuccess(success)
            }
        } else {
            // no auth, automatically allow
            authSuccess(true)
        }
    }
}
