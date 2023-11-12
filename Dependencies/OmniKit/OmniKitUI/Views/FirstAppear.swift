//
//  FirstAppear.swift
//  Omnipod
//
//  Created by Joe Moran on 9/24/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import SwiftUI

extension View {
    func onFirstAppear(_ action: @escaping () -> ()) -> some View {
        modifier(FirstAppear(action: action))
    }
}

private struct FirstAppear: ViewModifier {
    let action: () -> ()

    // State used to insure action is invoked here only once
    @State private var hasAppeared = false

    func body(content: Content) -> some View {
        content.onAppear {
            guard !hasAppeared else { return }
            hasAppeared = true
            action()
        }
    }
}
