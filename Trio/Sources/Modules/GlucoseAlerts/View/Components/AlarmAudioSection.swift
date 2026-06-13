import AVFoundation
import SwiftUI

struct AlarmAudioSection: View {
    @Binding var playsSound: Bool
    @Binding var soundFilename: String

    @State private var showTonePicker = false

    var body: some View {
        Section(header: Text("Alert Sound")) {
            Toggle("Play Sound", isOn: $playsSound)

            if playsSound {
                Button {
                    showTonePicker = true
                } label: {
                    HStack {
                        Text("Tone")
                        Spacer()
                        Text(AlarmSoundCatalog.displayName(for: soundFilename))
                            .foregroundColor(.secondary)
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                            .font(.footnote)
                    }
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showTonePicker) {
                    TonePickerSheet(selected: $soundFilename)
                }
            }
        }
        .listRowBackground(Color.chart)
    }
}

private struct TonePickerSheet: View {
    @Binding var selected: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self) private var appState
    @StateObject private var previewer = SoundPreviewPlayer()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(AlarmSoundCatalog.allFilenames, id: \.self) { filename in
                        TonePickerRow(
                            filename: filename,
                            selected: $selected,
                            previewer: previewer
                        )
                    }
                }.listRowBackground(Color.chart)
            }
            .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
            .navigationTitle("Choose Tone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        previewer.stop()
                        dismiss()
                    }
                }
            }
            .onDisappear { previewer.stop() }
        }
    }
}

private struct TonePickerRow: View {
    let filename: String
    @Binding var selected: String
    @ObservedObject var previewer: SoundPreviewPlayer

    var body: some View {
        HStack(spacing: 12) {
            Button {
                selected = filename
            } label: {
                Text(AlarmSoundCatalog.displayName(for: filename))
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                previewer.toggle(filename: filename)
            } label: {
                Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                    .font(.title3)
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)

            Spacer()

            Image(systemName: "checkmark")
                .foregroundColor(.accentColor)
                .opacity(filename == selected ? 1 : 0)
                .frame(width: 20)
        }
    }

    private var isPlaying: Bool { previewer.playing == filename }
}

/// Plays bundled alarm `.caf` files for in-picker auditioning. Mixable
/// `.playback` session so it ducks other audio without taking it over.
/// Not the critical-alert player — this one obeys the silent switch.
@MainActor private final class SoundPreviewPlayer: ObservableObject {
    @Published private(set) var playing: String?
    private var player: AVAudioPlayer?

    func toggle(filename: String) {
        if playing == filename {
            stop()
        } else {
            play(filename: filename)
        }
    }

    func play(filename: String) {
        stop()
        let resource = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension.isEmpty ? "caf" : (filename as NSString).pathExtension
        guard let url = Bundle.main.url(forResource: resource, withExtension: ext, subdirectory: "Sounds") else {
            return
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true, options: [])
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = previewDelegate
            p.prepareToPlay()
            guard p.play() else { return }
            player = p
            playing = filename
        } catch {
            debug(.service, "Audio preview failed for \(filename): \(error)")
        }
    }

    func stop() {
        player?.stop()
        player = nil
        playing = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private lazy var previewDelegate: PreviewDelegate = {
        let delegate = PreviewDelegate()
        delegate.onFinish = { [weak self] in self?.stop() }
        return delegate
    }()
}

private final class PreviewDelegate: NSObject, AVAudioPlayerDelegate {
    var onFinish: (() -> Void)?

    func audioPlayerDidFinishPlaying(_: AVAudioPlayer, successfully _: Bool) {
        Task { @MainActor in self.onFinish?() }
    }
}
