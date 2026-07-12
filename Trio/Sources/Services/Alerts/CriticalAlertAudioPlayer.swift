import AudioToolbox
import AVFoundation
import MediaPlayer
import os.log
import UIKit

@MainActor
final class CriticalAlertAudioPlayer {
    private let log = OSLog(subsystem: "org.nightscout.Trio", category: "CriticalAlertAudioPlayer")

    private var player: AVAudioPlayer?
    private var vibrationTimer: Timer?

    private let vibrationInterval: TimeInterval = 2.0
    private let boostedVolume: Float = 1.0
    private let volumeBooster = SystemVolumeBooster()

    var isPlaying: Bool { player?.isPlaying ?? false }

    /// Start (or restart) looping playback of a bundled critical alert sound.
    /// Loops until `stop()` is called from `retractAlert` /
    /// `handleAcknowledgement` in `BaseTrioAlertManager` — modeled on the
    /// LoopFollow / Jonas loop-failure alarm. `.playback` audio session gives
    /// the app a privileged background state so the alarm continues even if
    /// the user has the screen locked.
    func play(soundNamed soundName: String = "critical.caf") {
        stop()

        startVibration()

        let resource = (soundName as NSString).deletingPathExtension
        let ext = (soundName as NSString).pathExtension.isEmpty ? "caf" : (soundName as NSString).pathExtension
        let url = Bundle.main.url(forResource: resource, withExtension: ext, subdirectory: "Sounds")
            ?? Bundle.main.url(forResource: "critical", withExtension: "caf", subdirectory: "Sounds")
        guard let url else {
            os_log(
                "Neither %{public}@ nor critical.caf found in main bundle; audio fallback unavailable",
                log: log,
                type: .error,
                soundName
            )
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
            volumeBooster.boost(to: boostedVolume)

            let p = try AVAudioPlayer(contentsOf: url)
            p.numberOfLoops = -1
            p.volume = 1.0
            p.prepareToPlay()
            guard p.play() else {
                os_log("AVAudioPlayer.play() returned false for %{public}@", log: log, type: .error, url.lastPathComponent)
                try? session.setActive(false, options: [.notifyOthersOnDeactivation])
                return
            }
            player = p
            os_log("Started critical-alert audio playback (duration=%{public}.2fs)", log: log, type: .info, p.duration)
        } catch {
            os_log("Failed to start audio playback: %{public}@", log: log, type: .error, String(describing: error))
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
        guard player != nil || vibrationTimer != nil else { return }
        player?.stop()
        player = nil
        vibrationTimer?.invalidate()
        vibrationTimer = nil
        volumeBooster.restore()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        os_log("Stopped critical-alert audio playback", log: log, type: .info)
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
/// Best-effort: the slider only populates once the hosting view is in an
/// on-screen window, so it may no-op when the app is fully backgrounded. The
/// alarm's audio and vibration run regardless — this only makes them louder
/// when it can. Pre-boost level is restored on `restore()` unless the user
/// manually changed the volume in the meantime.
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
