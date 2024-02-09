import Combine
import SwiftUI

struct BolusConfirmationView: View {
    @EnvironmentObject var state: WatchStateModel

    @State var isCrownLeftOriented = WKInterfaceDevice.current().crownOrientation == .left
    @State var crownProgress: CGFloat = 100.0
    @State var progress: CGFloat = 0

    private let elementSize: CGFloat = 30

    @State var progressReturn: AnyCancellable?

    @State var done = false

    var body: some View {
        VStack {
            GeometryReader { geo in
                HStack(alignment: .top) {
                    Spacer().frame(width: elementSize / 2)
                    ZStack(alignment: .top) {
                        RoundedRectangle(cornerRadius: elementSize / 2, style: .circular)
                            .fill(.secondary)
                            .frame(width: elementSize, height: geo.size.height)
                            .opacity(0.2)

                        RoundedRectangle(cornerRadius: elementSize / 2, style: .circular)
                            .fill(Color.insulin)
                            .frame(width: elementSize, height: elementSize + (geo.size.height - elementSize) * progress / 100)
                            .opacity(0.2)

                        Image(systemName: done == true ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                            .resizable()
                            .foregroundColor(done == true ? .loopGreen : .insulin)
                            .frame(width: elementSize, height: elementSize)
                            .offset(y: (geo.size.height - elementSize) * progress / 100)

                    }.frame(maxWidth: .infinity, alignment: .center)
                    if isCrownLeftOriented {
                        Spacer().frame(width: elementSize / 2)
                    } else {
                        Image(systemName: "digitalcrown.arrow.counterclockwise.fill")
                            .resizable()
                            .frame(width: elementSize / 2, height: elementSize / 2)
                            .foregroundColor(.primary)
                            .transition(.opacity)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding()
            HStack(spacing: 16) {
                if isCrownLeftOriented {
                    Image(systemName: "digitalcrown.arrow.counterclockwise.fill")
                        .resizable()
                        .frame(width: elementSize / 2, height: elementSize / 2)
                        .foregroundColor(.primary)
                        .transition(.opacity)
                }
                Button {
                    WKInterfaceDevice.current().play(.click)
                    state.pendingBolus = nil
                    state.isConfirmationBolusViewActive = false
                }
                label: {
                    Text("Cancel")
                }
                if isCrownLeftOriented {
                    Spacer().frame(width: elementSize / 2)
                }
            }
        }
        .focusable(true)
        .digitalCrownRotation(
            $crownProgress,
            from: 0.0,
            through: 100.0,
            by: state.confirmBolusFaster ? 5 : 0.5,
            sensitivity: .high,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onChange(of: crownProgress) { _ in
            guard !done else { return }

            progressReturn?.cancel()
            progress = min(max(0, 100 - crownProgress), 100)
            if progress >= 100 {
                success()
            } else {
                progressReturn = Just(())
                    .delay(for: 0.1, scheduler: RunLoop.main)
                    .sink { _ in
                        crownProgress = 100
                        withAnimation {
                            progress = 0
                        }
                    }
            }
        }
    }

    private func success() {
        WKInterfaceDevice.current().play(.success)
        withAnimation {
            done = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            state.enactBolus()
        }
    }
}

struct BolusConfirmationView_Previews: PreviewProvider {
    static var previews: some View {
        BolusConfirmationView(progress: 50, done: false).environmentObject(WatchStateModel())
    }
}
