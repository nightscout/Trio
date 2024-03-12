//
//  BlueButtonStyle.swift
//  LibreTransmitterUI
//
//  Created by LoopKit Authors on 28/04/2021.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import SwiftUI

struct BlueButtonStyle: ButtonStyle {

  func makeBody(configuration: Self.Configuration) -> some View {

      configuration.label
          .font(.headline)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
          .contentShape(Rectangle())
          .padding()
          .foregroundColor(configuration.isPressed ? Color.white.opacity(0.5) : Color.white)
          .background(configuration.isPressed ? Color.blue.opacity(0.5) : Color.blue)
          .cornerRadius(10)

  }
}
