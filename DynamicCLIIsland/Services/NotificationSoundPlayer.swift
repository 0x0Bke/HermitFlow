import AVFoundation
import Foundation

final class NotificationSoundPlayer {
    private var player: AVAudioPlayer?

    func playNotificationPing() {
        guard let url = Bundle.main.url(forResource: "notification-ping", withExtension: "mp3") else {
            return
        }

        do {
            if player?.url != url {
                player = try AVAudioPlayer(contentsOf: url)
                player?.prepareToPlay()
            }

            player?.currentTime = 0
            player?.play()
        } catch {
            #if DEBUG
            print("Notification sound playback failed: \(error)")
            #endif
        }
    }
}
