import AppKit
import ApplicationServices
import CoreGraphics

enum ScreenPlacementMode: Equatable {
    case automatic
    case fixed(CGDirectDisplayID)
}

@MainActor
final class ScreenPlacementCoordinator {
    struct CompactMetrics {
        let isExternalDisplay: Bool
        let renderedScreenWidth: CGFloat
        let cameraHousingWidth: CGFloat
        let cameraHousingHeight: CGFloat
        let hasCameraHousing: Bool
    }

    func centeredOrigin(for screen: NSScreen, windowSize: CGSize, topInset: CGFloat = 0) -> CGPoint {
        centeredFrame(for: screen, windowSize: windowSize, topInset: topInset).origin
    }

    func centeredFrame(for screen: NSScreen, windowSize: CGSize, topInset: CGFloat = 0) -> NSRect {
        centeredFrame(in: screen.frame, windowSize: windowSize, topInset: topInset)
    }

    func centeredFrame(in screenFrame: CGRect, windowSize: CGSize, topInset: CGFloat = 0) -> NSRect {
        let origin = CGPoint(
            x: screenFrame.midX - (windowSize.width / 2),
            y: screenFrame.maxY - windowSize.height - topInset
        )
        return NSRect(origin: origin, size: windowSize)
    }

    func placementScreen(
        for window: NSWindow,
        mode: ScreenPlacementMode,
        preferMouseScreen: Bool = false
    ) -> NSScreen? {
        if case let .fixed(displayID) = mode,
           let fixedScreen = screen(for: displayID) {
            return fixedScreen
        }

        if let automaticScreen = automaticPlacementScreen(preferMouseScreen: preferMouseScreen) {
            return automaticScreen
        }

        if let screen = window.screen {
            return screen
        }

        return NSScreen.main ?? NSScreen.screens.first
    }

    func compactMetrics(for screen: NSScreen) -> CompactMetrics {
        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        let leftAuxArea = screen.auxiliaryTopLeftArea ?? .zero
        let rightAuxArea = screen.auxiliaryTopRightArea ?? .zero
        let displayID = screen.displayID
        let backingScaleFactor = max(screen.backingScaleFactor, 1)
        let renderedScreenWidth = screen.frame.width * backingScaleFactor
        let isExternalDisplay = displayID.map { !isBuiltInDisplay($0) } ?? false
        let hasCameraHousing = !leftAuxArea.isEmpty || !rightAuxArea.isEmpty
        let cameraHousingWidth = hasCameraHousing
            ? max(screen.frame.width - leftAuxArea.width - rightAuxArea.width, 0)
            : 0
        let cameraHousingHeight = max(leftAuxArea.height, rightAuxArea.height, screen.safeAreaInsets.top)

        return CompactMetrics(
            isExternalDisplay: isExternalDisplay,
            renderedScreenWidth: renderedScreenWidth,
            cameraHousingWidth: cameraHousingWidth,
            cameraHousingHeight: cameraHousingHeight > 0 ? cameraHousingHeight : menuBarHeight,
            hasCameraHousing: hasCameraHousing
        )
    }

    func topInset(isExpanded: Bool, hasCameraHousing: Bool) -> CGFloat {
        if !isExpanded {
            return hasCameraHousing ? -2 : 0
        }

        return hasCameraHousing ? -1 : 0
    }

    func titleForScreen(_ screen: NSScreen, displayID: CGDirectDisplayID) -> String {
        let typeLabel = isBuiltInDisplay(displayID) ? "Built-in" : "External"
        let sizeLabel = "\(Int(screen.frame.width))x\(Int(screen.frame.height))"
        return "\(screen.localizedName) (\(typeLabel), \(sizeLabel))"
    }

    func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first(where: { $0.displayID == displayID })
    }

    func isBuiltInDisplay(_ displayID: CGDirectDisplayID) -> Bool {
        CGDisplayIsBuiltin(displayID) != 0
    }

    private func automaticPlacementScreen(preferMouseScreen: Bool) -> NSScreen? {
        if let frontmostApplication = NSWorkspace.shared.frontmostApplication,
           let focusedScreen = focusedScreen(for: frontmostApplication) {
            return focusedScreen
        }

        if preferMouseScreen, let hoveredScreen = screenContainingMouse() {
            return hoveredScreen
        }

        if let hoveredScreen = screenContainingMouse() {
            return hoveredScreen
        }

        return NSScreen.main ?? NSScreen.screens.first
    }

    private func screenContainingMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
    }

    private func focusedScreen(for application: NSRunningApplication) -> NSScreen? {
        guard application.processIdentifier > 0 else {
            return nil
        }

        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        let windowAttributes: [CFString] = [
            kAXFocusedWindowAttribute as CFString,
            kAXMainWindowAttribute as CFString
        ]

        for attribute in windowAttributes {
            guard let windowElement = accessibilityElementAttribute(attribute, on: appElement) else {
                continue
            }

            if let frame = accessibilityFrame(for: windowElement),
               let screen = screen(matching: frame) {
                return screen
            }
        }

        return nil
    }

    private func accessibilityElementAttribute(_ attribute: CFString, on element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }

        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private func accessibilityFrame(for element: AXUIElement) -> CGRect? {
        guard
            let positionValue = accessibilityValueAttribute(kAXPositionAttribute as CFString, on: element, type: .cgPoint),
            let sizeValue = accessibilityValueAttribute(kAXSizeAttribute as CFString, on: element, type: .cgSize)
        else {
            return nil
        }

        let origin = CGPoint(x: positionValue.point.x, y: positionValue.point.y)
        let size = CGSize(width: sizeValue.size.width, height: sizeValue.size.height)
        guard size.width > 0, size.height > 0 else {
            return nil
        }

        return CGRect(origin: origin, size: size)
    }

    private func accessibilityValueAttribute(
        _ attribute: CFString,
        on element: AXUIElement,
        type: AXValueType
    ) -> AccessibilityValue? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success, let value, CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = unsafeDowncast(value, to: AXValue.self)
        switch type {
        case .cgPoint:
            var point = CGPoint.zero
            guard AXValueGetType(axValue) == .cgPoint, AXValueGetValue(axValue, .cgPoint, &point) else {
                return nil
            }
            return .point(point)
        case .cgSize:
            var size = CGSize.zero
            guard AXValueGetType(axValue) == .cgSize, AXValueGetValue(axValue, .cgSize, &size) else {
                return nil
            }
            return .size(size)
        default:
            return nil
        }
    }

    private func screen(matching frame: CGRect) -> NSScreen? {
        let normalizedFrame = frame.standardized
        guard !normalizedFrame.isNull, !normalizedFrame.isEmpty else {
            return nil
        }

        let bestScreen = NSScreen.screens.max { lhs, rhs in
            let leftIntersection = lhs.frame.intersection(normalizedFrame)
            let rightIntersection = rhs.frame.intersection(normalizedFrame)
            return (leftIntersection.width * leftIntersection.height) < (rightIntersection.width * rightIntersection.height)
        }

        if let bestScreen, bestScreen.frame.intersects(normalizedFrame) {
            return bestScreen
        }

        let frameCenter = CGPoint(x: normalizedFrame.midX, y: normalizedFrame.midY)
        return NSScreen.screens.first(where: { $0.frame.contains(frameCenter) })
    }
}

private enum AccessibilityValue {
    case point(CGPoint)
    case size(CGSize)

    var point: CGPoint {
        guard case let .point(value) = self else {
            return .zero
        }

        return value
    }

    var size: CGSize {
        guard case let .size(value) = self else {
            return .zero
        }

        return value
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        guard let value = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }

        return CGDirectDisplayID(value.uint32Value)
    }
}
