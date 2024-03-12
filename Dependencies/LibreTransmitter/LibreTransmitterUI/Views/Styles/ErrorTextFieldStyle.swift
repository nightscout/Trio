//
//  ErrorTextFieldStyle.swift
//  LibreTransmitterUI
//
//  Created by LoopKit Authors on 28/04/2021.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import SwiftUI

private struct ErrorTextFieldStyle: TextFieldStyle {
    public func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.red, lineWidth: 3))
    }
}
