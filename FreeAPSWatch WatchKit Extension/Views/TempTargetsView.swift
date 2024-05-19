import SwiftUI

struct TempTargetsView: View {
    @EnvironmentObject var state: WatchStateModel

    var body: some View {
        List {
            if state.tempTargets.isEmpty {
                Text("Set temp targets presets or override on iPhone first").padding()
            } else {
                ForEach(state.tempTargets) { target in
                    Button {
                        WKInterfaceDevice.current().play(.click)
                        state.enactTempTarget(id: target.id, typeTempTarget: target.typeTempTarget)
                    } label: {
                        VStack(alignment: .leading) {
                            HStack {
                                if target.typeTempTarget == .tempTarget {
                                    Image("target", bundle: nil)
                                        .renderingMode(.template)
                                        .resizable()
                                        .frame(width: 12, height: 12)
                                        .foregroundColor(.white)
                                } else
                                {
                                    Image(systemName: "person.3.sequence.fill")
                                        .renderingMode(.template)
                                        .resizable()
                                        .frame(width: 24, height: 12)
                                        .foregroundColor(.white)
                                }
                                Text(target.name)
                                if let until = target.until, until > Date() {
                                    Spacer()
                                    until.timeIntervalSinceNow >= (24 * 60 * 60 * 300) ? Text("Always") :
                                        Text(until, style: .timer).foregroundColor(.white)
                                }
                            }
                            Text(target.description).font(.caption2).foregroundColor(.white)
                        }
                    }.listRowBackground(
                        RoundedRectangle(cornerRadius: 15)
                            .background(Color.clear)
                            .foregroundColor(target.typeTempTarget == .tempTarget ? Color.tempBasal : Color.profil)
                    )
                }
            }

            Button {
                WKInterfaceDevice.current().play(.click)
                state.cancelTempTarget()
            } label: {
                Text("Cancel Temp Target/Profil")
            }
        }
        .navigationTitle("Temp Targets/Profil")
    }
}

struct TempTargetsView_Previews: PreviewProvider {
    static var previews: some View {
        let model = WatchStateModel()
        model.tempTargets = [
            TempTargetWatchPreset(
                name: "Target 0",
                id: UUID().uuidString,
                description: "blablabla",
                until: Date().addingTimeInterval(60 * 60), typeTempTarget: .tempTarget
            ),
            TempTargetWatchPreset(
                name: "target1",
                id: UUID().uuidString,
                description: "blablabla",
                until: nil,
                typeTempTarget: .tempTarget
            ),
            TempTargetWatchPreset(
                name: "🤖 Target 2",
                id: UUID().uuidString,
                description: "blablabla",
                until: nil,
                typeTempTarget: .tempTarget
            )
        ]
        return TempTargetsView().environmentObject(model)
    }
}
