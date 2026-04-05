import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = ProgressStore()
    private var window: NSWindow?
    private var statusItem: NSStatusItem?
    private var visibilityMenuItem: NSMenuItem?
    private var hermitLogoMenuItem: NSMenuItem?
    private var clawdLogoMenuItem: NSMenuItem?
    private var zenMuxLogoMenuItem: NSMenuItem?
    private var claudeCodeLogoMenuItem: NSMenuItem?
    private var codexColorLogoMenuItem: NSMenuItem?
    private var codexMonoLogoMenuItem: NSMenuItem?
    private var openAILogoMenuItem: NSMenuItem?
    private var approvalPreviewMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        createWindow()
        createStatusItem()
        registerScreenObservers()
        store.handleLaunch()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func createWindow() {
        let size = store.windowSize
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        window.hasShadow = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = false
        window.isMovable = false
        window.ignoresMouseEvents = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false

        let rootView = IslandRootView(store: store)
        window.contentView = NSHostingView(rootView: rootView)
        position(window: window, size: size, animated: false)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        position(window: window, size: size, animated: false)

        store.onWindowSizeChange = { [weak self] newSize in
            self?.position(window: window, size: newSize, animated: true)
        }

        self.window = window
    }

    private func createStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self

        let visibilityMenuItem = NSMenuItem(
            title: "Show/Hide Island",
            action: #selector(toggleWindowVisibility),
            keyEquivalent: ""
        )
        visibilityMenuItem.target = self
        menu.addItem(visibilityMenuItem)

        menu.addItem(.separator())

        let logoMenuItem = NSMenuItem(title: "Left Logo", action: nil, keyEquivalent: "")
        let logoSubmenu = NSMenu(title: "Left Logo")

        let hermitLogoMenuItem = NSMenuItem(
            title: ProgressStore.BrandLogo.hermit.menuTitle,
            action: #selector(selectHermitLogo),
            keyEquivalent: ""
        )
        hermitLogoMenuItem.target = self
        logoSubmenu.addItem(hermitLogoMenuItem)

        let clawdLogoMenuItem = NSMenuItem(
            title: ProgressStore.BrandLogo.clawd.menuTitle,
            action: #selector(selectClawdLogo),
            keyEquivalent: ""
        )
        clawdLogoMenuItem.target = self
        logoSubmenu.addItem(clawdLogoMenuItem)

        let claudeCodeLogoMenuItem = NSMenuItem(
            title: ProgressStore.BrandLogo.claudeCodeColor.menuTitle,
            action: #selector(selectClaudeCodeLogo),
            keyEquivalent: ""
        )
        claudeCodeLogoMenuItem.target = self
        logoSubmenu.addItem(claudeCodeLogoMenuItem)

        let codexColorLogoMenuItem = NSMenuItem(
            title: ProgressStore.BrandLogo.codexColor.menuTitle,
            action: #selector(selectCodexColorLogo),
            keyEquivalent: ""
        )
        codexColorLogoMenuItem.target = self
        logoSubmenu.addItem(codexColorLogoMenuItem)

        let codexMonoLogoMenuItem = NSMenuItem(
            title: ProgressStore.BrandLogo.codexMono.menuTitle,
            action: #selector(selectCodexMonoLogo),
            keyEquivalent: ""
        )
        codexMonoLogoMenuItem.target = self
        logoSubmenu.addItem(codexMonoLogoMenuItem)

        let openAILogoMenuItem = NSMenuItem(
            title: ProgressStore.BrandLogo.openAI.menuTitle,
            action: #selector(selectOpenAILogo),
            keyEquivalent: ""
        )
        openAILogoMenuItem.target = self
        logoSubmenu.addItem(openAILogoMenuItem)

        let zenMuxLogoMenuItem = NSMenuItem(
            title: ProgressStore.BrandLogo.zenmux.menuTitle,
            action: #selector(selectZenMuxLogo),
            keyEquivalent: ""
        )
        zenMuxLogoMenuItem.target = self
        logoSubmenu.addItem(zenMuxLogoMenuItem)

        menu.setSubmenu(logoSubmenu, for: logoMenuItem)
        menu.addItem(logoMenuItem)

        menu.addItem(.separator())

//        审批状态测试入口
//        let approvalPreviewMenuItem = NSMenuItem(
//            title: "Preview Approval UI",
//            action: #selector(toggleApprovalPreview),
//            keyEquivalent: ""
//        )
//        approvalPreviewMenuItem.target = self
//        menu.addItem(approvalPreviewMenuItem)
//
//        menu.addItem(.separator())

        let quitMenuItem = NSMenuItem(
            title: "Quit",
            action: #selector(quitFromMenu),
            keyEquivalent: "q"
        )
        quitMenuItem.target = self
        menu.addItem(quitMenuItem)

        if let button = statusItem.button {
            button.image = makeStatusBarImage()
            button.imagePosition = .imageOnly
            button.toolTip = "Dynamic CLI Island"
        }

        statusItem.menu = menu
        self.statusItem = statusItem
        self.visibilityMenuItem = visibilityMenuItem
        self.hermitLogoMenuItem = hermitLogoMenuItem
        self.clawdLogoMenuItem = clawdLogoMenuItem
        self.zenMuxLogoMenuItem = zenMuxLogoMenuItem
        self.claudeCodeLogoMenuItem = claudeCodeLogoMenuItem
        self.codexColorLogoMenuItem = codexColorLogoMenuItem
        self.codexMonoLogoMenuItem = codexMonoLogoMenuItem
        self.openAILogoMenuItem = openAILogoMenuItem
//        审批状态测试入口
//        self.approvalPreviewMenuItem = approvalPreviewMenuItem
        updateMenuState()
    }

    private func makeStatusBarImage() -> NSImage? {
        if let imageURL = Bundle.main.url(forResource: "claudecode-bar", withExtension: "png"),
           let image = NSImage(contentsOf: imageURL) {
            image.isTemplate = true
            image.size = NSSize(width: 18, height: 18)
            return image
        }

        return NSImage(systemSymbolName: "terminal.fill", accessibilityDescription: "Dynamic CLI Island")
    }

    private func position(window: NSWindow, size: CGSize, animated: Bool) {
        guard let screen = placementScreen(for: window) else {
            return
        }

        syncCompactMetrics(for: screen)
        let resolvedSize = store.windowSize
        let frame = screen.frame
        let leftAuxArea = screen.auxiliaryTopLeftArea ?? .zero
        let rightAuxArea = screen.auxiliaryTopRightArea ?? .zero
        let hasCameraHousing = !leftAuxArea.isEmpty || !rightAuxArea.isEmpty
        let topInset = topInsetForWindow(size: resolvedSize, hasCameraHousing: hasCameraHousing)
        let origin = CGPoint(
            x: frame.midX - resolvedSize.width / 2,
            y: frame.maxY - resolvedSize.height - topInset
        )
        let targetFrame = NSRect(origin: origin, size: resolvedSize)
        updatePanelHoverArming(for: targetFrame)

        if animated {
            let isExpanding = targetFrame.height > window.frame.height
            NSAnimationContext.runAnimationGroup { context in
                context.duration = isExpanding ? 0.22 : 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(targetFrame, display: true)
            }
        } else {
            window.setFrame(targetFrame, display: true)
        }
    }

    private func updatePanelHoverArming(for targetFrame: NSRect) {
        guard store.isExpanded else {
            return
        }

        let mouseLocation = NSEvent.mouseLocation
        if targetFrame.contains(mouseLocation) {
            store.armPanelHoverMonitoring()
        }
    }

    private func topInsetForWindow(size: CGSize, hasCameraHousing: Bool) -> CGFloat {
        if !store.isExpanded {
            return hasCameraHousing ? -2 : 0
        }

        return hasCameraHousing ? -1 : 0
    }

    private func syncCompactMetrics(for screen: NSScreen) {
        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        let leftAuxArea = screen.auxiliaryTopLeftArea ?? .zero
        let rightAuxArea = screen.auxiliaryTopRightArea ?? .zero
        let cameraHousingWidth = max(screen.frame.width - leftAuxArea.width - rightAuxArea.width, 0)
        let cameraHousingHeight = max(leftAuxArea.height, rightAuxArea.height, screen.safeAreaInsets.top)
        store.updateCameraHousingHeight(cameraHousingHeight > 0 ? cameraHousingHeight : menuBarHeight)
        store.updateCameraHousingWidth(cameraHousingWidth)
    }

    private func placementScreen(for window: NSWindow) -> NSScreen? {
        if let screen = window.screen {
            return screen
        }

        let mouseLocation = NSEvent.mouseLocation
        if let hoveredScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) {
            return hoveredScreen
        }

        return NSScreen.main ?? NSScreen.screens.first
    }

    private func registerScreenObservers() {
        let center = NotificationCenter.default

        center.addObserver(
            self,
            selector: #selector(handleScreenParametersChange(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        center.addObserver(
            self,
            selector: #selector(handleWindowScreenChange(_:)),
            name: NSWindow.didChangeScreenNotification,
            object: nil
        )

        center.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive(_:)),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    private func updateMenuState() {
        visibilityMenuItem?.title = "Show/Hide Island"
        hermitLogoMenuItem?.state = store.selectedLogo == .hermit ? .on : .off
        clawdLogoMenuItem?.state = store.selectedLogo == .clawd ? .on : .off
        zenMuxLogoMenuItem?.state = store.selectedLogo == .zenmux ? .on : .off
        claudeCodeLogoMenuItem?.state = store.selectedLogo == .claudeCodeColor ? .on : .off
        codexColorLogoMenuItem?.state = store.selectedLogo == .codexColor ? .on : .off
        codexMonoLogoMenuItem?.state = store.selectedLogo == .codexMono ? .on : .off
        openAILogoMenuItem?.state = store.selectedLogo == .openAI ? .on : .off
        approvalPreviewMenuItem?.state = store.approvalPreviewEnabled ? .on : .off
    }

    private var isWindowVisible: Bool {
        window?.isVisible == true
    }

    @objc
    private func toggleWindowVisibility() {
        guard let window else { return }

        if isWindowVisible {
            window.orderOut(nil)
        } else {
            position(window: window, size: store.windowSize, animated: false)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }

        updateMenuState()
    }

    @objc
    private func selectHermitLogo() {
        store.selectLogo(.hermit)
        updateMenuState()
    }

    @objc
    private func selectClawdLogo() {
        store.selectLogo(.clawd)
        updateMenuState()
    }

    @objc
    private func selectZenMuxLogo() {
        store.selectLogo(.zenmux)
        updateMenuState()
    }

    @objc
    private func selectClaudeCodeLogo() {
        store.selectLogo(.claudeCodeColor)
        updateMenuState()
    }

    @objc
    private func selectCodexColorLogo() {
        store.selectLogo(.codexColor)
        updateMenuState()
    }

    @objc
    private func selectCodexMonoLogo() {
        store.selectLogo(.codexMono)
        updateMenuState()
    }

    @objc
    private func selectOpenAILogo() {
        store.selectLogo(.openAI)
        updateMenuState()
    }

    @objc
    private func quitFromMenu() {
        store.quitApp()
    }

    @objc
    private func toggleApprovalPreview() {
        store.toggleApprovalPreview()
        updateMenuState()
    }

    @objc
    private func handleScreenParametersChange(_ notification: Notification) {
        guard let window else { return }
        position(window: window, size: store.windowSize, animated: false)
    }

    @objc
    private func handleWindowScreenChange(_ notification: Notification) {
        guard
            let changedWindow = notification.object as? NSWindow,
            changedWindow == window
        else { return }

        position(window: changedWindow, size: store.windowSize, animated: false)
    }

    @objc
    private func handleAppDidBecomeActive(_ notification: Notification) {
        store.handleAppDidBecomeActive()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        updateMenuState()
    }
}
