import AppKit
import AVFoundation
import Foundation

final class NotificationSoundPlayer {
    static let customSoundPathDefaultsKey = "HermitFlow.customNotificationSoundPath"
    static let customSoundBookmarkDefaultsKey = "HermitFlow.customNotificationSoundBookmark"

    private var bundledPlayer: AVAudioPlayer?
    private var customSound: NSSound?

    func playNotificationPing() {
        for candidate in notificationSoundCandidates() {
            if play(candidate) {
                return
            }
        }
    }

    private func play(_ resolvedSound: ResolvedNotificationSound) -> Bool {
        let stopAccessing = resolvedSound.startAccessingSecurityScopedResourceIfNeeded()
        defer { stopAccessing() }

        if resolvedSound.isCustom {
            return playCustomSound(resolvedSound)
        }

        return playBundledSound(resolvedSound)
    }

    private func playCustomSound(_ resolvedSound: ResolvedNotificationSound) -> Bool {
        let sound = NSSound(contentsOf: resolvedSound.url, byReference: false)
        guard let sound else {
            clearCustomSoundDefaults()
            return false
        }

        customSound?.stop()
        customSound = sound
        return sound.play()
    }

    private func playBundledSound(_ resolvedSound: ResolvedNotificationSound) -> Bool {
        do {
            if bundledPlayer?.url != resolvedSound.url {
                bundledPlayer = try AVAudioPlayer(contentsOf: resolvedSound.url)
                bundledPlayer?.prepareToPlay()
            }

            bundledPlayer?.currentTime = 0
            return bundledPlayer?.play() == true
        } catch {
            bundledPlayer = nil
            handlePlaybackFailure(for: resolvedSound, error: error)
            return false
        }
    }

    private func notificationSoundCandidates() -> [ResolvedNotificationSound] {
        let customSound = resolveCustomNotificationSound()
        let bundledSound = resolveBundledNotificationSound()

        switch (customSound, bundledSound) {
        case let (.some(customSound), .some(bundledSound)):
            return [customSound, bundledSound]
        case let (.some(customSound), .none):
            return [customSound]
        case let (.none, .some(bundledSound)):
            return [bundledSound]
        case (.none, .none):
            return []
        }
    }

    private func handlePlaybackFailure(for resolvedSound: ResolvedNotificationSound, error: Error) {
        if resolvedSound.isCustom {
            clearCustomSoundDefaults()
        }

        #if DEBUG
        print("Notification sound playback failed for \(resolvedSound.url.path): \(error)")
        #endif
    }

    private func clearCustomSoundDefaults() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Self.customSoundPathDefaultsKey)
        defaults.removeObject(forKey: Self.customSoundBookmarkDefaultsKey)
    }

    private func resolveBundledNotificationSound() -> ResolvedNotificationSound? {
        guard let bundledURL = Bundle.main.url(forResource: "notification-ping", withExtension: "mp3") else {
            return nil
        }
        return ResolvedNotificationSound(url: bundledURL, needsSecurityScopedAccess: false, isCustom: false)
    }

    private func resolveCustomNotificationSound() -> ResolvedNotificationSound? {
        let defaults = UserDefaults.standard

        if FileManager.default.fileExists(atPath: FilePaths.customNotificationSound.path) {
            persistPath(FilePaths.customNotificationSound.path)
            return ResolvedNotificationSound(
                url: FilePaths.customNotificationSound,
                needsSecurityScopedAccess: false,
                isCustom: true
            )
        }

        if let bookmarkData = defaults.data(forKey: Self.customSoundBookmarkDefaultsKey) {
            var isStale = false
            do {
                let url = try URL(
                    resolvingBookmarkData: bookmarkData,
                    options: [.withSecurityScope],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )

                if FileManager.default.fileExists(atPath: url.path) {
                    if isStale {
                        persistBookmark(for: url)
                    }
                    persistPath(url.path)
                    return ResolvedNotificationSound(url: url, needsSecurityScopedAccess: true, isCustom: true)
                }
            } catch {
                #if DEBUG
                print("Notification sound bookmark resolution failed: \(error)")
                #endif
            }
        }

        if let customPath = defaults.string(forKey: Self.customSoundPathDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !customPath.isEmpty {
            let customURL = URL(fileURLWithPath: customPath)
            if FileManager.default.fileExists(atPath: customURL.path) {
                return ResolvedNotificationSound(url: customURL, needsSecurityScopedAccess: false, isCustom: true)
            }
        }

        return nil
    }

    private func persistBookmark(for url: URL) {
        do {
            let bookmarkData = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmarkData, forKey: Self.customSoundBookmarkDefaultsKey)
        } catch {
            #if DEBUG
            print("Notification sound bookmark save failed: \(error)")
            #endif
        }
    }

    private func persistPath(_ path: String) {
        UserDefaults.standard.set(path, forKey: Self.customSoundPathDefaultsKey)
    }
}

private struct ResolvedNotificationSound {
    let url: URL
    let needsSecurityScopedAccess: Bool
    let isCustom: Bool

    func startAccessingSecurityScopedResourceIfNeeded() -> () -> Void {
        guard needsSecurityScopedAccess, url.startAccessingSecurityScopedResource() else {
            return {}
        }

        return {
            url.stopAccessingSecurityScopedResource()
        }
    }
}
