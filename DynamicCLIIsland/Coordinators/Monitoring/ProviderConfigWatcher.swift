import Darwin
import Foundation

@MainActor
final class ProviderConfigWatcher {
    private let fileURL: URL
    private let fileManager: FileManager
    private var monitor: DispatchSourceFileSystemObject?
    private var fileDescriptor: CInt = -1
    private var pollTimer: Timer?
    private var lastKnownModificationDate: Date?
    private var onChange: (() -> Void)?

    init(
        fileURL: URL = FilePaths.claudeProviderUsageConfig,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    func start(onChange: @escaping () -> Void) {
        self.onChange = onChange
        lastKnownModificationDate = modificationDate()
        startPollTimer()
        restartMonitor()
    }

    func stop() {
        monitor?.cancel()
        monitor = nil
        closeFileDescriptorIfNeeded()

        pollTimer?.invalidate()
        pollTimer = nil
        lastKnownModificationDate = nil
        onChange = nil
    }

    func restartMonitor() {
        monitor?.cancel()
        monitor = nil
        closeFileDescriptorIfNeeded()

        let path = fileURL.path
        guard fileManager.fileExists(atPath: path) else {
            return
        }

        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else {
            return
        }

        fileDescriptor = descriptor
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .attrib],
            queue: DispatchQueue.main
        )
        source.setEventHandler { [weak self] in
            self?.handleFilesystemEvent()
        }
        source.setCancelHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.closeFileDescriptorIfNeeded()
            }
        }
        monitor = source
        source.resume()
    }

    private func startPollTimer() {
        pollTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollChanges()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func pollChanges() {
        let currentModificationDate = modificationDate()
        if currentModificationDate != lastKnownModificationDate {
            lastKnownModificationDate = currentModificationDate
            onChange?()
            restartMonitor()
        } else if monitor == nil && fileManager.fileExists(atPath: fileURL.path) {
            restartMonitor()
        }
    }

    private func handleFilesystemEvent() {
        lastKnownModificationDate = modificationDate()
        onChange?()
        restartMonitor()
    }

    private func modificationDate() -> Date? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path) else {
            return nil
        }

        return attributes[.modificationDate] as? Date
    }

    private func closeFileDescriptorIfNeeded() {
        if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
        }
    }

    deinit {
        MainActor.assumeIsolated {
            stop()
        }
    }
}
