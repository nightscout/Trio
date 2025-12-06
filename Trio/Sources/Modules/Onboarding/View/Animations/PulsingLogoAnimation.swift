//
//  PulsingLogoAnimation.swift
//  Trio
//
//  Created by Marvin Polscheit on 11.04.25.
//
import SwiftUI

struct PulsingLogoAnimation: View {
    @State private var scale = 0.5
    @State private var opacity = 0.0
    @State private var rotation = 0.0
    @State private var isPulsing = false

    var body: some View {
        Image("trioCircledNoBackground")
            .resizable()
            .scaledToFit()
            .frame(height: 100)
            .scaleEffect(scale)
            .opacity(opacity)
            .rotationEffect(.degrees(rotation))
            .scaleEffect(isPulsing ? 1.1 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.0)) {
                    scale = 1.0
                    opacity = 1.0
                    rotation = 360
                }

                withAnimation(.easeInOut(duration: 1.0).repeatForever()) {
                    isPulsing.toggle()
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    withAnimation(.easeOut(duration: 1.0)) {
                        isPulsing = false
                    }
                }
            }
    }
}
