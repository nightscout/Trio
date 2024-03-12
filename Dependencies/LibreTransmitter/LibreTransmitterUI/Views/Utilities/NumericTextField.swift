//
//  NumericTextField.swift
//  LibreTransmitterUI
//
//  Created by LoopKit Authors on 23/05/2021.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import SwiftUI
import Combine

// Decided to use shared instance instead of .environmentObject()
class FormErrorState: ObservableObject {
    @Published var childrenErrorStatus: [String: Bool] = [:]

    var hasAnyError: Bool {
        !childrenErrorStatus.isEmpty && childrenErrorStatus.values.contains(true)
    }

    static var shared = FormErrorState()
}

private var valueNumberFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.locale = Locale.current
    formatter.minimumFractionDigits = 1

    return formatter
}()

private var intNumberFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.numberStyle = .none
    formatter.locale = Locale.current
    formatter.minimumFractionDigits = 1
    formatter.maximumFractionDigits = 0

    return formatter
}()

public struct NumericTextField: View {

    static func localeTextToDouble(_ text: String) -> Double? {
        valueNumberFormatter.number(from: text)?.doubleValue
    }
    static func doubleToLocateText(_ dbl: Double) -> String? {
        valueNumberFormatter.string(from: dbl as NSNumber)
    }

    static func localeTextToInt(_ text: String) -> Int? {
        intNumberFormatter.number(from: text)?.intValue
    }
    static func intToLocateText(_ dbl: Double) -> String? {
        intNumberFormatter.string(from: dbl as NSNumber)
    }

    @State private(set) var hasError = false {
        didSet {
            if oldValue != hasError {
                formstate.childrenErrorStatus[description] = hasError
            }
        }
    }

    @ObservedObject var formstate: FormErrorState = .shared

    var textField: some View {

        TextField(description, text: $numericString)
            .onReceive(Just(numericString)) { value in

                print("onreceive called")

                guard let newValue = Self.localeTextToDouble(value) else {
                    print("onreceive guard failed")
                    hasError = true

                    return
                }

                let isInteger = newValue.truncatingRemainder(dividingBy: 1.0) == 0.0

                if requiresIntegerValue && !isInteger {
                    // consider this or coloring view to indicate error
                    // self.numericString = "\(numericValue)"
                    hasError = true
                    return

                }

                if self.numericValue != newValue {
                    self.numericValue = newValue
                }

                hasError = false

        }
       .onAppear {
            if requiresIntegerValue {
                self.numericString = Self.intToLocateText(numericValue) ?? "unknown"
            } else {
                self.numericString = Self.doubleToLocateText(numericValue) ?? "unknown"
            }
        }
        .textFieldStyle(RoundedBorderTextFieldStyle())
        .disableAutocorrection(true)
        .keyboardType(.decimalPad)
        .border(Color(UIColor.separator))
        .disabled(isReadOnly)

    }

    var textFieldWithError : some View {
        textField
        .overlay(
            VStack {
                if hasError {
                    Rectangle()
                    .stroke(Color.red, lineWidth: 1)
                } else {
                    EmptyView()
                }

            }
        )
    }

    public var body: some View {
        HStack {
            if showDescription {
                Text("\(description)")
            }
            textFieldWithError
        }
        .padding(1)

    }

    init(description: String, showDescription: Bool, numericValue: Binding<Double>, isReadOnly: Bool=false, formErrorState: FormErrorState?=nil ) {
        self.description = description
        self._numericValue = numericValue
        self.requiresIntegerValue = false
        self.isReadOnly = isReadOnly
        self.showDescription = showDescription
        if let formErrorState {
            self.formstate = formErrorState
        }
    }

    init(description: String, showDescription: Bool, numericValue wrapper: Binding<Int>, isReadOnly: Bool=false, formErrorState: FormErrorState?=nil ) {
        self.description = description
        self.requiresIntegerValue = true
        self.isReadOnly = isReadOnly
        self.showDescription = showDescription

        if let formErrorState {
            self.formstate = formErrorState
        }

        // allows an int to behave as a double, should be just fine in most cases (that we care about)
        let bd = Binding<Double>(get: { Double(wrapper.wrappedValue) },
                              set: { wrapper.wrappedValue = Int($0) })
        self._numericValue = bd

    }

    var description: String
    var showDescription: Bool
    var isReadOnly: Bool = false

    var requiresIntegerValue = false
    // numericvalue assumes that all ints can be encoded as doubles, which might not be true always though.
    @Binding var numericValue: Double
    @State private var numericString: String  = ""

}
