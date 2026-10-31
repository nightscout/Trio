import AudioToolbox
import AVFoundation
import MediaPlayer
import UIKit

@MainActor
final class CriticalAlertAudioPlayer {
    private var player: AVAudioPlayer?
    private var stopTimer: Timer?
    private var vibrationTimer: Timer?

    private let vibrationInterval: TimeInterval = 2.0
    /// System volume floor for critical alarms. The alarm has to be audible
    /// with the ringer down, but forcing 100% wakes the whole household and
    /// leaves the user no way to turn it down. Raise only up to this floor;
    /// anything already louder is left alone.
    private let minimumSystemVolume: Float = 0.5
    private let volumeBooster = SystemVolumeBooster()

    var isPlaying: Bool { player?.isPlaying ?? false }

    /// Shortest an alarm rings. A floor, not a cap: whole passes of the sound
    /// run until it is reached, so a short tone repeats and a long one plays
    /// through once rather than being cut off mid-phrase.
    nonisolated static let minBurstDuration: TimeInterval = 6

    /// Longest an alarm rings, so an unexpectedly long sound can't run on.
    nonisolated static let maxBurstDuration: TimeInterval = 30

    /// Whole passes of `duration`, enough to reach `minBurstDuration`, capped.
    nonisolated static func burstDuration(forSoundOfDuration duration: TimeInterval) -> TimeInterval {
        guard duration > 0 else { return minBurstDuration }
        let passes = max(1, Int((minBurstDuration / duration).rounded(.up)))
        return min(maxBurstDuration, duration * Double(passes))
    }

    /// Burst length for a bundled sound, or the floor if it can't be read.
    nonisolated static func burstDuration(forSoundNamed soundName: String) -> TimeInterval {
        guard let url = soundURL(named: soundName), let p = try? AVAudioPlayer(contentsOf: url) else {
            return minBurstDuration
        }
        return burstDuration(forSoundOfDuration: p.duration)
    }

    nonisolated private static func soundURL(named soundName: String) -> URL? {
        let resource = (soundName as NSString).deletingPathExtension
        let ext = (soundName as NSString).pathExtension.isEmpty ? "caf" : (soundName as NSString).pathExtension
        return Bundle.main.url(forResource: resource, withExtension: ext)
            ?? Bundle.main.url(forResource: "critical", withExtension: "caf")
    }

    /// Play one burst of a bundled critical alert sound (see
    /// `burstDuration`), then stop on its own. `retractAlert` /
    /// `handleAcknowledgement` in `BaseTrioAlertManager` can end it sooner.
    /// `.playback` audio session gives the app a privileged background state
    /// so the alarm plays even if the user has the screen locked.
    func play(soundNamed soundName: String = "critical.caf") {
        stop()

        startVibration()
        // Bounds vibration if the audio setup below fails; re-armed to the
        // sound's burst length once it is known.
        scheduleStop(after: Self.minBurstDuration)

        guard let url = Self.soundURL(named: soundName) else {
            error(.alerts, "Critical alert sound \(soundName) and fallback sound missing, audio fallback unavailable")
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            // .playback ignores the silent switch and Focus modes. Must be
            // mixable: iOS refuses to activate a non-mixable session from
            // the background (AVAudioSessionErrorCodeCannotInterruptOthers,
            // 560557684 "Session activation failed"). .duckOthers +
            // .mixWithOthers ducks/mixes our alarm over other audio instead
            // of failing outright. Mixable .playback still plays at full
            // volume when nothing else is active and still bypasses the
            // silent switch.
            try session.setCategory(.playback, mode: .default, options: [.duckOthers, .mixWithOthers])
            try session.setActive(true, options: [])
            volumeBooster.boost(to: minimumSystemVolume)

            let p = try AVAudioPlayer(contentsOf: url)
            p.numberOfLoops = -1
            p.volume = 1.0
            p.prepareToPlay()
            guard p.play() else {
                error(.alerts, "Critical alert audio did not start for \(url.lastPathComponent)")
                try? session.setActive(false, options: [.notifyOthersOnDeactivation])
                return
            }
            player = p
            let burst = Self.burstDuration(forSoundOfDuration: p.duration)
            scheduleStop(after: burst)
            info(
                .alerts,
                "Critical alert audio started, sound length \(String(format: "%.2f", p.duration)) s, burst \(String(format: "%.2f", burst)) s"
            )
        } catch let playbackError {
            error(.alerts, "Critical alert audio playback failed", error: playbackError)
        }
    }

    private func scheduleStop(after interval: TimeInterval) {
        stopTimer?.invalidate()
        stopTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.stop() }
        }
    }

    private func startVibration() {
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        vibrationTimer = Timer.scheduledTimer(withTimeInterval: vibrationInterval, repeats: true) { _ in
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
    }

    /// Stop playback if any. Safe to call when not playing.
    func stop() {
        guard player != nil || stopTimer != nil || vibrationTimer != nil else { return }
        player?.stop()
        player = nil
        stopTimer?.invalidate()
        stopTimer = nil
        vibrationTimer?.invalidate()
        vibrationTimer = nil
        volumeBooster.restore()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        debug(.alerts, "Critical alert audio stopped")
    }
}

/// Best-effort override of the system output volume.
///
/// iOS has no public API to set the hardware volume. `MPVolumeView` hosts a
/// `UISlider` that drives the system volume when its value changes — the
/// long-standing workaround. Used ONLY for critical-alert audio on builds
/// without the Critical Alerts entitlement: without it an urgent-low alarm
/// can be silent when the ringer is down overnight.
///
/// Raises the system volume to a floor, never to maximum, and never lowers a
/// user who is already louder than the floor.
///
/// Best-effort: the slider only populates once the hosting view is in an
/// on-screen window, so it may no-op when the app is fully backgrounded. The
/// alarm's audio and vibration run regardless. Pre-boost level is restored on
/// `restore()` unless the user manually changed the volume in the meantime.
@MainActor private final class SystemVolumeBooster {
    private let volumeView = MPVolumeView(frame: CGRect(x: -2000, y: -2000, width: 1, height: 1))
    private var savedVolume: Float?
    private var targetVolume: Float?
    private var generation = 0

    func boost(to target: Float) {
        guard let window = Self.activeWindow() else { return }
        attach(to: window)
        generation &+= 1
        let gen = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, gen == self.generation, let slider = self.slider() else { return }
            let current = slider.value
            guard current < target else { return }
            self.savedVolume = current
            self.targetVolume = target
            slider.setValue(target, animated: false)
        }
    }

    func restore() {
        generation &+= 1
        if let saved = savedVolume,
           let target = targetVolume,
           let slider = slider(),
           abs(slider.value - target) < 0.05
        {
            slider.setValue(saved, animated: false)
        }
        savedVolume = nil
        targetVolume = nil
        volumeView.removeFromSuperview()
    }

    private func attach(to window: UIWindow) {
        volumeView.alpha = 0.0001
        volumeView.isUserInteractionEnabled = false
        if volumeView.superview !== window {
            volumeView.removeFromSuperview()
            window.addSubview(volumeView)
        }
    }

    private func slider() -> UISlider? {
        volumeView.subviews.compactMap { $0 as? UISlider }.first
    }

    private static func activeWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let active = scenes.first { $0.activationState == .foregroundActive }
        return active?.windows.first(where: { $0.isKeyWindow })
            ?? active?.windows.first
            ?? scenes.flatMap(\.windows).first
    }
}
