import AVFoundation
import Foundation
import MediaPlayer
import UIKit

/// Manages alarm sound playback for prolonged loop failure.
///
/// Uses `AVAudioSession.Category.playback` to bypass the mute switch and
/// `MPVolumeView` to optionally override the system volume.
/// Modeled after LoopFollow's alarm sound implementation.
@MainActor
final class AlarmSound: NSObject, ObservableObject {
    static let shared = AlarmSound()

    // MARK: - Public State

    @Published private(set) var isAlarmActive = false

    var isPlaying: Bool {
        audioPlayer?.isPlaying == true
    }

    // MARK: - Persisted State

    @Persisted(key: "AlarmSound.snoozedUntil") var snoozedUntil: Date = .distantPast
    @Persisted(key: "AlarmSound.loopFailureAcknowledged") private var loopFailureAcknowledged: Bool = false

    // MARK: - Private

    private var audioPlayer: AVAudioPlayer?
    private var systemOutputVolumeBeforeOverride: Float?
    private let defaultSoundName = "CriticalAlarm"

    override private init() {
        super.init()
    }

    // MARK: - Playback

    /// Start the loop-failure alarm sound.
    /// - Parameters:
    ///   - overrideVolume: Whether to temporarily raise the system volume.
    ///   - volume: The target system volume (0.0-1.0) when overriding.
    func play(overrideVolume: Bool = false, volume: Float = 0.8) {
        guard !isPlaying else { return }
        guard shouldFire() else { return }

        guard let soundURL = Bundle.main.url(forResource: defaultSoundName, withExtension: "caf") else {
            debug(.service, "AlarmSound: sound file \(defaultSoundName).caf not found in bundle")
            return
        }

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)

            audioPlayer = try AVAudioPlayer(contentsOf: soundURL)
            audioPlayer?.delegate = self
            audioPlayer?.numberOfLoops = -1 // loop indefinitely

            if systemOutputVolumeBeforeOverride == nil {
                systemOutputVolumeBeforeOverride = AVAudioSession.sharedInstance().outputVolume
            }

            guard audioPlayer?.prepareToPlay() == true else {
                debug(.service, "AlarmSound: audio player failed to prepare")
                return
            }

            guard audioPlayer?.play() == true else {
                debug(.service, "AlarmSound: audio player failed to play")
                return
            }

            if overrideVolume {
                MPVolumeView.setVolume(volume)
            }

            isAlarmActive = true
            debug(.service, "AlarmSound: loop-failure alarm started")
        } catch {
            debug(.service, "AlarmSound: failed to play - \(error)")
        }
    }

    /// Stop the alarm sound and restore volume.
    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        isAlarmActive = false
        restoreSystemOutputVolume()
    }

    /// Play a short test of the alarm sound, applying volume override if enabled.
    func playTest(overrideVolume: Bool = false, volume: Float = 0.8) {
        guard !isPlaying else { return }

        guard let soundURL = Bundle.main.url(forResource: defaultSoundName, withExtension: "caf") else {
            debug(.service, "AlarmSound: sound file \(defaultSoundName).caf not found in bundle")
            return
        }

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)

            if overrideVolume, systemOutputVolumeBeforeOverride == nil {
                systemOutputVolumeBeforeOverride = AVAudioSession.sharedInstance().outputVolume
            }

            audioPlayer = try AVAudioPlayer(contentsOf: soundURL)
            audioPlayer?.delegate = self
            audioPlayer?.numberOfLoops = 0 // play once

            audioPlayer?.prepareToPlay()
            audioPlayer?.play()

            if overrideVolume {
                MPVolumeView.setVolume(volume)
            }
        } catch {
            debug(.service, "AlarmSound: test play failed - \(error)")
        }
    }

    // MARK: - Snooze / Acknowledge

    /// Snooze the alarm for a duration. Alarm will re-fire after snooze expires if the condition persists.
    func snooze(for duration: TimeInterval) {
        stop()
        snoozedUntil = duration > 0 ? Date().addingTimeInterval(duration) : .distantPast
        debug(.service, "AlarmSound: snoozed for \(duration)s")
    }

    /// Acknowledge the alarm. Won't re-fire until `loopDidResume()` clears the flag.
    func acknowledge() {
        loopFailureAcknowledged = true
        debug(.service, "AlarmSound: acknowledged loop failure")
        stop()
    }

    /// Called when the loop successfully completes. Stops any active alarm and resets the acknowledge state.
    func loopDidResume() {
        if isPlaying {
            debug(.service, "AlarmSound: loop resumed, stopping active alarm")
            stop()
        }
        if loopFailureAcknowledged {
            loopFailureAcknowledged = false
            debug(.service, "AlarmSound: loop resumed, reset loop failure acknowledge")
        }
    }

    // MARK: - Guard Check

    /// Returns true if the alarm should fire (not playing, not snoozed, not acknowledged).
    func shouldFire() -> Bool {
        if isPlaying { return false }
        if snoozedUntil > Date() { return false }
        return !loopFailureAcknowledged
    }

    // MARK: - Volume

    private func restoreSystemOutputVolume() {
        guard let volumeBeforeOverride = systemOutputVolumeBeforeOverride else { return }
        MPVolumeView.setVolume(volumeBeforeOverride)
        systemOutputVolumeBeforeOverride = nil
    }
}

// MARK: - AVAudioPlayerDelegate

extension AlarmSound: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_: AVAudioPlayer, successfully flag: Bool) {
        debug(.service, "AlarmSound: audioPlayerDidFinishPlaying (success: \(flag))")
        // Restore volume after test playback finishes (numberOfLoops = 0)
        // For looping alarms (numberOfLoops = -1), this only fires on interruption — stop() handles volume restore
        restoreSystemOutputVolume()
    }

    func audioPlayerDecodeErrorDidOccur(_: AVAudioPlayer, error: Error?) {
        debug(.service, "AlarmSound: decode error - \(error?.localizedDescription ?? "unknown")")
    }
}

// MARK: - MPVolumeView Extension

extension MPVolumeView {
    static func setVolume(_ volume: Float) {
        let volumeView = MPVolumeView(frame: .zero)
        let slider = volumeView.subviews.first(where: { $0 is UISlider }) as? UISlider
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            slider?.value = volume
        }
        // Add to window invisibly so the slider is functional
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first
        {
            volumeView.alpha = 0.000001
            window.addSubview(volumeView)
        }
    }
}
