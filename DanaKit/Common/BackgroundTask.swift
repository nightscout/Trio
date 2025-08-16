import AVFoundation

/// A trick used to keep the app alive
class BackgroundTask {
    // MARK: - Vars

    var player = AVAudioPlayer()
    var timer = Timer()

    // MARK: - Methods

    func startBackgroundTask() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(interruptedAudio),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
        playAudio()
    }

    func stopBackgroundTask() {
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.interruptionNotification, object: nil)
        player.stop()
    }

    @objc private func interruptedAudio(_ notification: Notification) {
        if notification.name == AVAudioSession.interruptionNotification, notification.userInfo != nil {
            let info = notification.userInfo!
            var intValue = 0
            (info[AVAudioSessionInterruptionTypeKey]! as AnyObject).getValue(&intValue)
            if intValue == 1 { playAudio() }
        }
    }

    private func playAudio() {
        do {
            let bundle = Bundle(for: DanaKitHUDProvider.self).path(forResource: "blank", ofType: "wav")
            let alertSound = URL(fileURLWithPath: bundle!)
            // try AVAudioSession.sharedInstance().setCategory(AVAudioSession.Category.playback)
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: .mixWithOthers)
            try AVAudioSession.sharedInstance().setActive(true)
            try player = AVAudioPlayer(contentsOf: alertSound)
            // Play audio forever by setting num of loops to -1
            player.numberOfLoops = -1
            player.volume = 0.01
            player.prepareToPlay()
            player.play()
        } catch { print(error)
        }
    }
}
