import AVFoundation
import SwiftUI

struct AlarmAudioSection: View {
    @Binding var playsSound: Bool
    @Binding var soundFilename: String
    /// Which alarm is being edited — decides which themed sets are offered.
    let scope: AlarmSoundCatalog.Scope

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
                    TonePickerSheet(selected: $soundFilename, scope: scope)
                }
            }
        }
        .listRowBackground(Color.chart)
    }
}

private struct TonePickerSheet: View {
    @Binding var selected: String
    let scope: AlarmSoundCatalog.Scope

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self) private var appState
    @StateObject private var previewer = SoundPreviewPlayer()
    /// Start expanded when the current pick lives in there, so the selection
    /// is never hidden behind a closed group.
    @State private var showOtherSounds: Bool

    init(selected: Binding<String>, scope: AlarmSoundCatalog.Scope) {
        _selected = selected
        self.scope = scope
        _showOtherSounds = State(
            initialValue: AlarmSoundCatalog.entry(forFilename: selected.wrappedValue)?.isGeneric ?? false
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(AlarmSoundCatalog.themedEntries(for: scope)) { entry in
                        TonePickerRow(entry: entry, selected: $selected, previewer: previewer)
                    }
                }.listRowBackground(Color.chart)

                Section {
                    DisclosureGroup(isExpanded: $showOtherSounds) {
                        ForEach(AlarmSoundCatalog.genericTones) { entry in
                            TonePickerRow(entry: entry, selected: $selected, previewer: previewer)
                        }
                    } label: {
                        Text("Other Sounds")
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
        // Sheets don't reliably inherit the presenting hierarchy's tint on
        // re-render — pin Trio's accent explicitly so buttons don't fall
        // back to system blue after a selection change.
        .tint(Color.tabBar)
    }
}

private struct TonePickerRow: View {
    let entry: AlarmSoundCatalog.Entry
    @Binding var selected: String
    @ObservedObject var previewer: SoundPreviewPlayer

    private var isSelected: Bool { entry.filenames.contains(selected) }

    /// The file this row stands for: the picked variant while selected,
    /// otherwise the entry's default.
    private var filename: String {
        isSelected ? selected : entry.defaultOption.filename
    }

    private var option: AlarmSoundCatalog.Option {
        entry.option(forFilename: filename) ?? entry.defaultOption
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            row
            if isSelected, entry.selector != .none {
                variantControl
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    private var row: some View {
        HStack(spacing: 12) {
            Button {
                selected = filename
            } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(Color.tabBar)
                    .frame(width: 20)

                Text(entry.displayName)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)

            Spacer()

            Button {
                previewer.toggle(filename: filename)
            } label: {
                Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                    .font(.title3)
                    .foregroundColor(Color.tabBar)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(
                isPlaying
                    ? String(localized: "Stop preview", comment: "Accessibility: stop tone preview")
                    : String(localized: "Play preview", comment: "Accessibility: play tone preview")
            ))

            Spacer()
        }
    }

    @ViewBuilder private var variantControl: some View {
        switch entry.selector {
        case .urgency: urgencySlider
        case .voice: voicePicker
        case .none: EmptyView()
        }
    }

    /// Discrete Mild / Medium / Harsh. Changing it auditions the new level —
    /// the point is hearing how the character changes.
    private var urgencySlider: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Urgency Level")
                Spacer()
                Text(option.displayName).foregroundColor(.secondary)
            }
            .font(.footnote)

            Slider(
                value: Binding(
                    get: { Double(entry.options.firstIndex(of: option) ?? 0) },
                    set: { raw in
                        let index = min(max(Int(raw.rounded()), 0), entry.options.count - 1)
                        select(entry.options[index])
                    }
                ),
                in: 0 ... Double(max(entry.options.count - 1, 1)),
                step: 1
            )
            .padding(.vertical)
            .tint(Color.tabBar)
            .accessibilityLabel(Text("Urgency Level"))
            .accessibilityValue(Text(option.displayName))

            HStack {
                ForEach(Array(entry.options.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Spacer() }
                    Text(item.displayName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .accessibilityHidden(true)
        }
        .padding(.leading, 32)
    }

    private var voicePicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Select a Voice").font(.footnote)
            Picker("", selection: Binding(
                get: { option.id },
                set: { id in
                    guard let match = entry.options.first(where: { $0.id == id }) else { return }
                    select(match)
                }
            )) {
                ForEach(entry.options) { Text($0.displayName).tag($0.id) }
            }
            .pickerStyle(.segmented)
        }
        .padding(.leading, 32)
    }

    private func select(_ option: AlarmSoundCatalog.Option) {
        guard option.filename != selected else { return }
        selected = option.filename
        previewer.play(filename: option.filename)
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
        guard let url = Bundle.main.url(forResource: resource, withExtension: ext) else {
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
            warning(.alerts, "Alarm sound preview failed for \(filename)", error: error)
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
