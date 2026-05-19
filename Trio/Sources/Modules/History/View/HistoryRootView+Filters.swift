import SwiftUI

extension History.RootView {
    var filterTreatmentsButton: some View {
        Button(action: {
            showTreatmentTypeFilter.toggle()
        }) {
            HStack {
                Text("Filter")
                Image(
                    systemName: selectedTreatmentTypes.count == History.TreatmentType.allCases.count
                        ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill"
                )
                if selectedTreatmentTypes.count < History.TreatmentType.allCases.count {
                    Text(verbatim: "(\(selectedTreatmentTypes.count)/\(History.TreatmentType.allCases.count))")
                }
            }.foregroundColor(Color.accentColor)
        }
        .popover(isPresented: $showTreatmentTypeFilter, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 20) {
                Button(action: {
                    if selectedTreatmentTypes.count == History.TreatmentType.allCases.count {
                        // Deselect all - keep at least one selected
                        selectedTreatmentTypes = []
                    } else {
                        // Select all
                        selectedTreatmentTypes = Set(History.TreatmentType.allCases)
                    }
                }) {
                    HStack(spacing: 20) {
                        Image(
                            systemName: selectedTreatmentTypes.count == History.TreatmentType.allCases.count
                                ? "checkmark.square.fill" : "square"
                        )
                        .frame(width: 20)
                        .foregroundColor(Color.accentColor)
                        Text(
                            selectedTreatmentTypes.count == History.TreatmentType.allCases
                                .count ? String(localized: "Deselect All") : String(localized: "Select All")
                        )
                        .foregroundColor(Color.primary)
                    }.padding(4)
                }
                .buttonStyle(.borderless)

                Divider()

                ForEach(History.TreatmentType.allCases, id: \.rawValue) { treatmentType in
                    Button(action: {
                        toggleTreatmentType(treatmentType)
                    }) {
                        HStack(spacing: 20) {
                            Image(
                                systemName: selectedTreatmentTypes
                                    .contains(treatmentType) ? "checkmark.square.fill" : "square"
                            )
                            .frame(width: 20)
                            .foregroundColor(Color.accentColor)
                            Text(treatmentType.displayName)
                                .foregroundColor(Color.primary)
                        }.padding(4)
                    }
                    .buttonStyle(.borderless)
                }

                Divider()

                Button("Done") {
                    showTreatmentTypeFilter = false
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(.borderless)
            }
            .padding()
            .presentationCompactAdaptation(.popover)
            .background(Color.chart)
        }
    }

    var filterFutureEntriesButton: some View {
        Button(
            action: {
                showFutureEntries.toggle()
            },
            label: {
                HStack {
                    Text(showFutureEntries ? String(localized: "Hide Future") : String(localized: "Show Future"))
                        .foregroundColor(Color.accentColor)
                    Image(systemName: showFutureEntries ? "eye.slash" : "eye")
                        .foregroundColor(Color.accentColor)
                }
            }
        ).buttonStyle(.borderless)
    }

    func toggleTreatmentType(_ type: History.TreatmentType) {
        if selectedTreatmentTypes.contains(type) {
            selectedTreatmentTypes.remove(type)
        } else {
            selectedTreatmentTypes.insert(type)
        }
    }
}
