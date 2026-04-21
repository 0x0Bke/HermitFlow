import CoreGraphics
import XCTest
@testable import HermitFlow

final class ArchitectureLogicTests: XCTestCase {
    func testVersionCompareHandlesTagsMissingPatchAndPreReleaseSuffixes() {
        XCTAssertEqual(GitHubReleaseUpdateChecker.compareVersions("v1.2.10", "1.2.9"), .orderedDescending)
        XCTAssertEqual(GitHubReleaseUpdateChecker.compareVersions("1.2", "1.2.0"), .orderedSame)
        XCTAssertEqual(GitHubReleaseUpdateChecker.compareVersions("1.2.0-beta", "1.2.1"), .orderedAscending)
    }

    @MainActor
    func testScreenPlacementCenteredFrameCalculationUsesTopInset() {
        let coordinator = ScreenPlacementCoordinator()

        let frame = coordinator.centeredFrame(
            in: CGRect(x: 100, y: 50, width: 1440, height: 900),
            windowSize: CGSize(width: 360, height: 80),
            topInset: 12
        )

        XCTAssertEqual(frame.origin.x, 640)
        XCTAssertEqual(frame.origin.y, 858)
        XCTAssertEqual(frame.size.width, 360)
        XCTAssertEqual(frame.size.height, 80)
    }

    @MainActor
    func testScreenPlacementTopInsetPreservesCompactCameraHousingRules() {
        let coordinator = ScreenPlacementCoordinator()

        XCTAssertEqual(coordinator.topInset(isExpanded: false, hasCameraHousing: false), 0)
        XCTAssertEqual(coordinator.topInset(isExpanded: false, hasCameraHousing: true), -2)
        XCTAssertEqual(coordinator.topInset(isExpanded: true, hasCameraHousing: false), 0)
        XCTAssertEqual(coordinator.topInset(isExpanded: true, hasCameraHousing: true), -1)
    }

    func testApprovalMergerSelectsNewestRequest() {
        let older = makeApproval(id: "older", createdAt: Date(timeIntervalSince1970: 10), source: .codex)
        let newer = makeApproval(id: "newer", createdAt: Date(timeIntervalSince1970: 20), source: .claude)

        XCTAssertEqual(ApprovalRequestMerger.merge(older, newer)?.id, "newer")
        XCTAssertEqual(ApprovalRequestMerger.merge(newer, nil)?.id, "newer")
        XCTAssertNil(ApprovalRequestMerger.merge(nil, nil))
    }

    func testActivityMergerOrdersSessionsAndMergesStatusErrorsApprovalAndUsage() {
        let older = Date(timeIntervalSince1970: 100)
        let newer = Date(timeIntervalSince1970: 200)
        let codexApproval = makeApproval(id: "codex", createdAt: older, source: .codex)
        let claudeApproval = makeApproval(id: "claude", createdAt: newer, source: .claude)

        let codexSnapshot = ActivitySourceSnapshot(
            sessions: [
                makeSession(id: "codex-idle", origin: .codex, state: .idle, updatedAt: older)
            ],
            statusMessage: "Watching Codex activity",
            lastUpdatedAt: older,
            errorMessage: "Codex error",
            approvalRequest: codexApproval,
            usageSnapshots: [
                ProviderUsageSnapshot(
                    origin: .codex,
                    shortWindowRemaining: 0.2,
                    longWindowRemaining: 0.4,
                    updatedAt: older
                )
            ]
        )
        let claudeSnapshot = ActivitySourceSnapshot(
            sessions: [
                makeSession(id: "claude-running", origin: .claude, state: .running, updatedAt: newer)
            ],
            statusMessage: "Watching Claude activity",
            lastUpdatedAt: newer,
            errorMessage: "Claude error",
            approvalRequest: claudeApproval,
            usageSnapshots: [
                ProviderUsageSnapshot(
                    origin: .codex,
                    shortWindowRemaining: 0.7,
                    longWindowRemaining: 0.8,
                    updatedAt: newer
                ),
                ProviderUsageSnapshot(
                    origin: .claude,
                    shortWindowRemaining: 0.3,
                    longWindowRemaining: 0.6,
                    updatedAt: newer
                )
            ]
        )

        let merged = ActivitySnapshotMerger.merge(codexSnapshot, claudeSnapshot)

        XCTAssertEqual(merged.sessions.map(\.id), ["claude-running", "codex-idle"])
        XCTAssertEqual(merged.statusMessage, "Watching Codex + Claude Code activity")
        XCTAssertEqual(merged.lastUpdatedAt, newer)
        XCTAssertEqual(merged.errorMessage, "Codex error · Claude error")
        XCTAssertEqual(merged.approvalRequest?.id, "claude")
        XCTAssertEqual(Set(merged.usageSnapshots.map(\.origin)), [.codex, .claude])
        XCTAssertEqual(merged.usageSnapshots.first(where: { $0.origin == .codex })?.shortWindowRemaining, 0.7)
    }

    private func makeApproval(id: String, createdAt: Date, source: SessionOrigin) -> ApprovalRequest {
        ApprovalRequest(
            id: id,
            contextTitle: nil,
            commandSummary: "Run command",
            commandText: "echo test",
            rationale: nil,
            focusTarget: nil,
            createdAt: createdAt,
            source: source,
            resolutionKind: .localHTTPHook
        )
    }

    private func makeSession(
        id: String,
        origin: SessionOrigin,
        state: IslandCodexActivityState,
        updatedAt: Date
    ) -> AgentSessionSnapshot {
        AgentSessionSnapshot(
            id: id,
            origin: origin,
            title: id,
            detail: "detail",
            activityState: state,
            runningDetail: nil,
            updatedAt: updatedAt,
            cwd: nil,
            focusTarget: nil,
            freshness: .live
        )
    }
}
