import SwiftUI

struct LoopStatusView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(AppState.self) var appState

    var state: Home.StateModel

    @State private var sheetContentHeight = CGFloat.zero
    // Help Sheet
    @State var isHelpSheetPresented: Bool = false
    @State var helpSheetDetent = PresentationDetent.fraction(0.9)

    @State private var statusTitle: String = ""
    @State private var lastDetermination: OrefDetermination?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Current Loop Status").bold()

                        Text(statusTitle)
                            .font(.headline)
                            .bold()
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .foregroundColor(statusBadgeTextColor)
                            .background(statusBadgeColor)
                            .clipShape(Capsule())
                    }

                    Spacer()

                    Button(
                        action: {
                            isHelpSheetPresented.toggle()
                        },
                        label: {
                            Image(systemName: "questionmark.circle")
                        }
                    )
                }.padding(.top, 20)

                if let errorMessage = state.errorMessage, let date = state.errorDate {
                    Group {
                        Text("Loop at \(Formatter.dateFormatter.string(from: date)) failed.").font(.headline)
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(errorMessage).font(.caption).fixedSize(horizontal: false, vertical: true)
                    }.foregroundColor(.loopRed)
                }

                if let determination = state.determinationsFromPersistence.first {
                    if determination.glucose == 400 {
                        Text("Invalid CGM reading (HIGH).")
                            .bold()
                            .padding(.top)
                            .foregroundStyle(Color.loopRed)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("SMBs and Non-Zero Temp. Basal Rates are disabled.")
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)

                    } else {
                        Text("Latest Raw Algorithm Output")
                            .bold()
                            .padding(.top)

                        Text(
                            "Trio is currently using these metrics and values as determined by the oref algorithm:"
                        )
                        .font(.subheadline)
                        .lineLimit(nil)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                        TagCloudView(
                            tags: getComputedTags(determination),
                            shouldParseToMmolL: state.units == .mmolL
                        )

                        Text("Current Algorithm Reasoning").bold().padding(.top)

                        Text(
                            self
                                .parseReasonConclusion(
                                    determination.reasonConclusion,
                                    isMmolL: state.units == .mmolL
                                )
                        )
                        .font(.subheadline)
                        .lineLimit(nil)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text("No recent oref algorithm determination.")
                }

                Spacer()

                Button {
                    state.isLoopStatusPresented.toggle()
                } label: {
                    Text("Got it!").bold().frame(maxWidth: .infinity, minHeight: 30, alignment: .center)
                }
                .buttonStyle(.bordered)
                .padding(.top)
            }
            .padding(.vertical)
            .padding(.horizontal, 20)
            .ignoresSafeArea(edges: .top)
            .background {
                GeometryReader { geo in
                    Color.clear
                        .preference(key: ContentSizeKey.self, value: geo.size)
                }
            }
            .onAppear {
                setStatusTitle()
            }
            .sheet(isPresented: $isHelpSheetPresented) {
                LoopStatusHelpView(state: state, helpSheetDetent: $helpSheetDetent, isHelpSheetPresented: $isHelpSheetPresented)
            }
        }
        .onAppear {
            lastDetermination = state.determinationsFromPersistence.first
        }
        .presentationDetents([.height(sheetContentHeight)])
        .presentationDragIndicator(.visible)
        .onPreferenceChange(ContentSizeKey.self) { newSize in
            sheetContentHeight = newSize.height
        }
        .background(appState.trioBackgroundColor(for: colorScheme))
        .scrollContentBackground(.hidden)
    }

    private var statusBadgeColor: Color {
        guard let determination = state.determinationsFromPersistence.first, determination.timestamp != nil
        else {
            // previously the .timestamp property was used here because this only gets updated when the reportenacted function in the aps manager gets called
            return .secondary
        }

        let delta = state.timerDate.timeIntervalSince(state.lastLoopDate) - 30

        if delta <= 5.minutes.timeInterval {
            guard determination.timestamp != nil else {
                return .loopYellow
            }
            return .loopGreen
        } else if delta <= 10.minutes.timeInterval {
            return .loopYellow
        } else {
            return .loopRed
        }
    }

    private var statusBadgeTextColor: Color {
        if statusBadgeColor == .secondary {
            .black
        } else {
            colorScheme == .dark ? Color(red: 25.0 / 255.0, green: 39.0 / 255.0, blue: 53.0 / 255.0, opacity: 1.0) : .white
        }
    }

    private func setStatusTitle() {
        if let determination = state.determinationsFromPersistence.first, let deliverAt = determination.deliverAt {
            let minutesAgo = abs(deliverAt.timeIntervalSinceNow) / 60

            if deliverAt < Date().addingTimeInterval(-5 * 60) {
                let roundedMinutes = Int(minutesAgo.rounded())
                statusTitle = String(
                    localized: "Trio has not looped in \(roundedMinutes) minutes."
                )
            } else {
                statusTitle = String(
                    localized: "Enacted at \(Formatter.dateFormatter.string(from: deliverAt))"
                )
            }
        } else if let determination = lastDetermination, let deliverAt = determination.deliverAt {
            let minutesAgo = abs(deliverAt.timeIntervalSinceNow) / 60

            if deliverAt < Date().addingTimeInterval(-5 * 60) {
                let roundedMinutes = Int(minutesAgo.rounded())
                statusTitle = String(
                    localized: "Trio has not looped in \(roundedMinutes) minutes."
                )
            } else {
                statusTitle = String(
                    localized: "Enacted at \(Formatter.dateFormatter.string(from: deliverAt))"
                )
            }
        } else {
            statusTitle = String(localized: "Not looping.")
        }
    }

    // TODO: Consolidate all mmol parsing methods (in TagCloudView, NightscoutManager and HomeRootView) to one central func
    private func parseReasonConclusion(_ reasonConclusion: String, isMmolL: Bool) -> String {
        let patterns = [
            "minGuardBG\\s*-?\\d+\\.?\\d*<-?\\d+\\.?\\d*", // minGuardBG x<y
            "Eventual BG\\s*-?\\d+\\.?\\d*\\s*>=\\s*-?\\d+\\.?\\d*", // Eventual BG x >= target
            "Eventual BG\\s*-?\\d+\\.?\\d*\\s*<\\s*-?\\d+\\.?\\d*", // Eventual BG x < target
            "(\\S+)\\s+(-?\\d+\\.?\\d*)\\s*>\\s*(\\d+)%\\s+of\\s+BG\\s+(-?\\d+\\.?\\d*)" // maxDelta x > y% of BG z
        ]
        let pattern = patterns.joined(separator: "|")
        let regex = try! NSRegularExpression(pattern: pattern)

        func convertToMmolL(_ value: String) -> String {
            if let glucoseValue = Double(value.replacingOccurrences(of: "[^\\d.-]", with: "", options: .regularExpression)) {
                let mmolValue = Decimal(glucoseValue).asMmolL
                return mmolValue.description
            }
            return value
        }

        let matches = regex.matches(
            in: reasonConclusion,
            range: NSRange(reasonConclusion.startIndex..., in: reasonConclusion)
        )
        var updatedConclusion = reasonConclusion

        for match in matches.reversed() {
            guard let range = Range(match.range, in: reasonConclusion) else { continue }
            let matchedString = String(reasonConclusion[range])

            if isMmolL {
                if matchedString.contains("<"), matchedString.contains("Eventual BG"), !matchedString.contains("=") {
                    // Handle "Eventual BG x < target" pattern
                    let parts = matchedString.components(separatedBy: "<")
                    if parts.count == 2 {
                        let bgPart = parts[0].replacingOccurrences(of: "Eventual BG", with: "")
                            .trimmingCharacters(in: .whitespaces)
                        let targetValue = parts[1].trimmingCharacters(in: .whitespaces)
                        let formattedBGPart = convertToMmolL(bgPart)
                        let formattedTargetValue = convertToMmolL(targetValue)
                        let formattedString = "Eventual BG \(formattedBGPart)<\(formattedTargetValue)"
                        updatedConclusion.replaceSubrange(range, with: formattedString)
                    }
                } else if matchedString.contains("<"), matchedString.contains("minGuardBG") {
                    // Handle "minGuardBG x<y" pattern
                    let parts = matchedString.components(separatedBy: "<")
                    if parts.count == 2 {
                        let firstValue = parts[0].trimmingCharacters(in: .whitespaces)
                        let secondValue = parts[1].trimmingCharacters(in: .whitespaces)
                        let formattedFirstValue = convertToMmolL(firstValue)
                        let formattedSecondValue = convertToMmolL(secondValue)
                        let formattedString = "minGuardBG \(formattedFirstValue)<\(formattedSecondValue)"
                        updatedConclusion.replaceSubrange(range, with: formattedString)
                    }
                } else if matchedString.contains(">=") {
                    // Handle "Eventual BG x >= target" pattern
                    let parts = matchedString.components(separatedBy: " >= ")
                    if parts.count == 2 {
                        let firstValue = parts[0].replacingOccurrences(of: "Eventual BG", with: "")
                            .trimmingCharacters(in: .whitespaces)
                        let secondValue = parts[1].trimmingCharacters(in: .whitespaces)
                        let formattedFirstValue = convertToMmolL(firstValue)
                        let formattedSecondValue = convertToMmolL(secondValue)
                        let formattedString = "Eventual BG \(formattedFirstValue) >= \(formattedSecondValue)"
                        updatedConclusion.replaceSubrange(range, with: formattedString)
                    }
                } else if let localMatch = regex.firstMatch(
                    in: matchedString,
                    range: NSRange(matchedString.startIndex..., in: matchedString)
                ) {
                    // Handle "maxDelta 37 > 20% of BG 95" style
                    if match.numberOfRanges == 5 {
                        let metric = String(matchedString[Range(localMatch.range(at: 1), in: matchedString)!])
                        let firstValue = String(matchedString[Range(localMatch.range(at: 2), in: matchedString)!])
                        let percentage = String(matchedString[Range(localMatch.range(at: 3), in: matchedString)!])
                        let bgValue = String(matchedString[Range(localMatch.range(at: 4), in: matchedString)!])

                        let formattedFirstValue = convertToMmolL(firstValue)
                        let formattedBGValue = convertToMmolL(bgValue)

                        let formattedString = "\(metric) \(formattedFirstValue) > \(percentage)% of BG \(formattedBGValue)"
                        updatedConclusion.replaceSubrange(range, with: formattedString)
                    }
                }
            } else {
                // When isMmolL is false, ensure the original value is retained without duplication
                updatedConclusion.replaceSubrange(range, with: matchedString)
            }
        }

        return updatedConclusion.capitalizingFirstLetter()
    }

    private func getComputedTags(_ determination: OrefDetermination) -> [String] {
        var tags: [String] = determination.reasonParts

        if state.isSmoothingEnabled {
            tags.append("Smoothing: On")
        }

        if let currentTDD = state.fetchedTDDs.first?.totalDailyDose, currentTDD != 0 {
            tags.append("TDD: \(currentTDD)")
        }

        return tags
    }
}

struct ContentSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        // If multiple views report sizes, pick whichever logic you prefer:
        // - The largest height
        // - The sum
        // For a single child, just use nextValue() directly if you like.
        let next = nextValue()
        if next.height > value.height {
            value = next
        }
    }
}
