import SwiftUI

struct AlarmEnumMenuPicker<E: CaseIterable & Hashable & DayNightDisplayable>: View {
    let title: String
    @Binding var selection: E
    let allowed: [E]

    init(title: String, selection: Binding<E>, allowed: [E]) {
        self.title = title
        _selection = selection
        self.allowed = allowed
    }

    init(title: String, selection: Binding<E>) where E.AllCases: RandomAccessCollection {
        self.title = title
        _selection = selection
        allowed = Array(E.allCases)
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Picker("", selection: $selection) {
                ForEach(allowed, id: \.self) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.menu)
            .onAppear(perform: validate)
            .onChange(of: allowed) { _, _ in validate() }
        }
    }

    private func validate() {
        guard !allowed.contains(selection), let first = allowed.first else { return }
        selection = first
    }
}
