//
//  BluetoothRequiredView.swift
//  Trio
//
//  Created by Cengiz Deniz on 27.04.25.
//
import SwiftUI

public struct BluetoothRequiredView: View {
    public var body: some View {
        VStack(alignment: .center, spacing: 12) {
            HStack {
                Image("logo.bluetooth.capsule.portrait.fill")
                    .foregroundStyle(Color.red)
                Text("Bluetooth Required")
            }
            .font(.headline.bold())
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .overlay(
                Capsule()
                    .stroke(Color.red.opacity(0.75), lineWidth: 2)
            )

            Text("Tap to Enable Bluetooth in iOS Settings")
                .font(.subheadline.bold())
                .foregroundStyle(Color.primary.opacity(0.8))
        }
        .onTapGesture {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }
    }
}
