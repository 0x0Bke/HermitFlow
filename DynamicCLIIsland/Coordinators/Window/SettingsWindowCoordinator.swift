import AppKit
import SwiftUI

@MainActor
final class SettingsWindowCoordinator: NSObject, NSWindowDelegate {
    private var panel: NSWindow?
    private var onClose: (() -> Void)?

    var isVisible: Bool {
        panel?.isVisible == true
    }

    var currentWindow: NSWindow? {
        panel
    }

    func present<Content: View>(
        rootView: Content,
        referenceWindow: NSWindow?,
        keepIslandVisible: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.onClose = onClose
        keepIslandVisible()

        if let panel {
            if panel.isMiniaturized {
                panel.deminiaturize(nil)
            }
            panel.contentView = NSHostingView(rootView: rootView)
            panel.makeKeyAndOrderFront(nil)
            keepIslandVisible()
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let panel = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 812, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.title = "Settings"
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.isReleasedWhenClosed = false
        panel.titlebarAppearsTransparent = false
        panel.isMovableByWindowBackground = true
        panel.level = .normal
        panel.collectionBehavior = []
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: rootView)

        position(panel, relativeTo: referenceWindow)
        panel.makeKeyAndOrderFront(nil)
        keepIslandVisible()
        NSApp.activate(ignoringOtherApps: true)
        self.panel = panel
    }

    func close() {
        panel?.close()
    }

    func handleReopen() -> Bool {
        guard let panel else {
            return false
        }

        if panel.isMiniaturized {
            panel.deminiaturize(nil)
        }

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow, closingWindow === panel else {
            return
        }

        onClose?()
    }

    private func position(_ panel: NSWindow, relativeTo referenceWindow: NSWindow?) {
        let panelSize = panel.frame.size
        let referenceFrame = referenceWindow?.frame ?? NSScreen.main?.visibleFrame ?? .zero
        let visibleFrame = referenceWindow?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let originX = referenceFrame.midX - panelSize.width / 2
        let preferredGap: CGFloat = 72
        let minimumBottomMargin: CGFloat = 12
        let preferredY = referenceFrame.minY - panelSize.height - preferredGap
        let minimumY = visibleFrame.minY + minimumBottomMargin
        let originY = max(preferredY, minimumY)
        panel.setFrameOrigin(NSPoint(x: originX.rounded(), y: originY.rounded()))
    }
}
