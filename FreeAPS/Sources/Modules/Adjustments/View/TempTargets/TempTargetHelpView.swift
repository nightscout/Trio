NavigationStack {
                    List {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(
                                "A Temporary Target replaces the current Target Glucose specified in Therapy settings."
                            )
                            Text(
                                "Depending on the Algorithm > Target Behavior settings, these temporary glucose targets can also raise Insulin Sensitivity for high targets or lower sensitivity for low targets."
                            )
                            Text(
                                "Furthermore, you could adjust that sensitivity change independently from the Half Basal Exercise Target specified in Algorithm > Target Behavior settings by deliberatly setting a customized Insulin Percentage for a Temp Target."
                            )
                            Text(
                                "A pre-condition to have Temp Targets adjust Sensitivity is that the respective Target Behavior settings High Temp Target Raises Sensitivity or Low Temp Target Lowers Sensitivity are set to enabled!"
                            )
                        }
                    }
                    .padding(.trailing, 10)
                    .navigationBarTitle("Help", displayMode: .inline)

                    Button { state.isHelpSheetPresented.toggle() }
                    label: { Text("Got it!").frame(maxWidth: .infinity, alignment: .center) }
                        .buttonStyle(.bordered)
                        .padding(.top)
                }
                .padding()
                .presentationDetents(
                    [.fraction(0.9), .large],
                    selection: $state.helpSheetDetent
                )
            }