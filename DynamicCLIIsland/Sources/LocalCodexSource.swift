import AppKit
import Foundation

struct LocalCodexSource: @unchecked Sendable {
    private let stateDatabaseURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex/state_5.sqlite")
    private let logsDatabaseURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex/logs_1.sqlite")
    private let sessionsDirectoryURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex/sessions")
    private let globalStateURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex/.codex-global-state.json")
    private let tuiLogURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex/log/codex-tui.log")
    private let recentThreadLimit = 8
    private let idleSessionLookback: TimeInterval = 6 * 60 * 60
    private let unconfirmedDesktopSessionLookback: TimeInterval = 5 * 60
    private let fallbackTUILookback: TimeInterval = 6 * 60 * 60
    private let staleSessionThreshold: TimeInterval = 3 * 60
    private let recentSessionScanBytes = 768 * 1024
    private let runningSignalMaxAge: TimeInterval = 30
    private let terminalStatusHold: TimeInterval = 18
    private let successSettleDelay: TimeInterval = 1
    private let shellSnapshotsDirectoryURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex/shell_snapshots")
    private let sessionFileLocator = SessionFileLocator(
        rootURL: URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex/sessions")
    )
    private let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    func fetchActivity() -> ActivitySourceSnapshot {
        guard
            FileManager.default.fileExists(atPath: stateDatabaseURL.path),
            FileManager.default.fileExists(atPath: logsDatabaseURL.path)
        else {
            return ActivitySourceSnapshot(
                sessions: [],
                statusMessage: "Local Codex state unavailable",
                lastUpdatedAt: .now,
                errorMessage: nil,
                approvalRequest: nil
            )
        }

        let threadSnapshots = fetchRecentThreadSnapshots(limit: recentThreadLimit)
        guard !threadSnapshots.isEmpty else {
            return ActivitySourceSnapshot(
                sessions: [],
                statusMessage: "Waiting for Codex activity",
                lastUpdatedAt: .now,
                errorMessage: nil,
                approvalRequest: nil
            )
        }

        var sessions: [AgentSessionSnapshot] = []
        var newestApprovalRequest: ApprovalRequest?
        let globalState = fetchGlobalState()

        for threadSnapshot in threadSnapshots {
            let sessionFileURL = fetchSessionFileURL(for: threadSnapshot.threadID)
            let sessionMeta = sessionFileURL.flatMap(fetchSessionMeta(from:))
            let sessionHints = sessionFileURL.flatMap(fetchSessionActivityHints(from:))
            let terminalClient = detectTerminalClient(for: threadSnapshot.threadID)
            let resolvedCWD = resolvedWorkingDirectory(sessionMeta: sessionMeta, threadSnapshot: threadSnapshot)
            let hasActiveWorkspaceMatch = hasActiveWorkspaceMatch(cwd: resolvedCWD, globalState: globalState)
            let shouldPreferDesktopOrigin = hasActiveWorkspaceMatch && threadSnapshot.threadSource == "vscode"
            let focusTarget = makeFocusTarget(
                threadID: threadSnapshot.threadID,
                sessionMeta: sessionMeta,
                fallbackSource: threadSnapshot.threadSource,
                fallbackCWD: resolvedCWD,
                terminalClient: terminalClient,
                preferDesktopOrigin: shouldPreferDesktopOrigin
            )
            let approvalRequest = sessionFileURL.flatMap { fetchPendingApproval(in: $0, focusTarget: focusTarget) }
            let activityState = approvalRequest != nil ? .running : deriveActivityState(from: threadSnapshot, sessionHints: sessionHints)
            let updatedAt = Date(timeIntervalSince1970: max(threadSnapshot.threadUpdatedAt, sessionHints?.latestKnownAt ?? 0))
            let freshness = sessionFreshness(
                activityState: activityState,
                updatedAt: updatedAt,
                focusTarget: focusTarget
            )
            let clientOrigin = focusTarget?.clientOrigin
            let isUnavailableDesktopSession = if let clientOrigin,
                                                clientOrigin == .codexDesktop || clientOrigin == .codexVSCode {
                !isClientRunning(clientOrigin) && !hasActiveWorkspaceMatch
            } else {
                false
            }
            let hasExplicitOrigin = if let sessionMeta {
                sessionMeta.originDescription != "Local Codex"
            } else {
                threadSnapshot.threadSource == "vscode" || threadSnapshot.threadSource == "cli"
            }
            let isPresentableSession = approvalRequest != nil
                || focusTarget != nil
                || !resolvedCWD.isEmpty
                || hasExplicitOrigin

            if isUnavailableDesktopSession {
                continue
            }

            if !isPresentableSession {
                continue
            }

            if let approvalRequest,
               newestApprovalRequest == nil || approvalRequest.createdAt > newestApprovalRequest!.createdAt {
                newestApprovalRequest = approvalRequest
            }

            let shouldIncludeSession = approvalRequest != nil
                || activityState != .idle
                || shouldRetainIdleSession(
                    updatedAt: updatedAt,
                    focusTarget: focusTarget,
                    hasWorkingDirectory: !resolvedCWD.isEmpty,
                    hasActiveWorkspaceMatch: hasActiveWorkspaceMatch
                )
            guard shouldIncludeSession else {
                continue
            }

            let detail = !resolvedCWD.isEmpty
                ? resolvedCWD
                : "Watching local Codex activity"

            sessions.append(
                AgentSessionSnapshot(
                    id: threadSnapshot.threadID,
                    origin: .codex,
                    title: sessionTitle(
                        sessionMeta: sessionMeta,
                        fallbackSource: threadSnapshot.threadSource,
                        terminalClient: terminalClient,
                        preferDesktopOrigin: shouldPreferDesktopOrigin
                    ),
                    detail: detail,
                    activityState: activityState,
                    updatedAt: updatedAt,
                    cwd: resolvedCWD.isEmpty ? nil : resolvedCWD,
                    focusTarget: focusTarget,
                    freshness: freshness
                )
            )
        }

        let knownThreadIDs = Set(threadSnapshots.map(\.threadID))
        sessions.append(contentsOf: fetchFallbackCLISessions(excluding: knownThreadIDs))

        let lastUpdatedAt = sessions.map(\.updatedAt).max() ?? .now
        let statusMessage: String
        if sessions.isEmpty {
            statusMessage = "Waiting for Codex activity"
        } else if sessions.count > 1 {
            statusMessage = "Watching \(sessions.count) local Codex sessions"
        } else {
            statusMessage = "Watching local Codex activity"
        }

        return ActivitySourceSnapshot(
            sessions: sessions,
            statusMessage: statusMessage,
            lastUpdatedAt: lastUpdatedAt,
            errorMessage: nil,
            approvalRequest: newestApprovalRequest
        )
    }

    func fetchLatestApprovalRequest() -> ApprovalRequest? {
        guard FileManager.default.fileExists(atPath: stateDatabaseURL.path) else {
            return nil
        }

        let threadReferences = fetchRecentThreadReferences(limit: 4)
        guard !threadReferences.isEmpty else {
            return nil
        }

        let globalState = fetchGlobalState()
        var newestApprovalRequest: ApprovalRequest?

        for threadReference in threadReferences {
            let sessionFileURL = fetchSessionFileURL(for: threadReference.threadID)
            let sessionMeta = sessionFileURL.flatMap(fetchSessionMeta(from:))
            let terminalClient = detectTerminalClient(for: threadReference.threadID)
            let resolvedCWD = resolvedWorkingDirectory(sessionMeta: sessionMeta, fallbackCWD: threadReference.cwd)
            let hasActiveWorkspaceMatch = hasActiveWorkspaceMatch(cwd: resolvedCWD, globalState: globalState)
            let shouldPreferDesktopOrigin = hasActiveWorkspaceMatch && threadReference.threadSource == "vscode"
            let focusTarget = makeFocusTarget(
                threadID: threadReference.threadID,
                sessionMeta: sessionMeta,
                fallbackSource: threadReference.threadSource,
                fallbackCWD: resolvedCWD,
                terminalClient: terminalClient,
                preferDesktopOrigin: shouldPreferDesktopOrigin
            )

            guard let sessionFileURL,
                  let approvalRequest = fetchPendingApproval(in: sessionFileURL, focusTarget: focusTarget) else {
                continue
            }

            if newestApprovalRequest == nil || approvalRequest.createdAt > newestApprovalRequest!.createdAt {
                newestApprovalRequest = approvalRequest
            }
        }

        return newestApprovalRequest
    }

    private func deriveActivityState(
        from snapshot: LocalCodexThreadSnapshot,
        sessionHints: LocalCodexSessionActivityHints?
    ) -> IslandCodexActivityState {
        let now = Date().timeIntervalSince1970
        let latestCompletionAt = max(snapshot.completedAt, sessionHints?.taskCompletedAt ?? 0)
        let latestFailureAt = max(snapshot.failedAt, sessionHints?.taskFailedAt ?? 0)
        let latestTerminalAt = max(latestCompletionAt, latestFailureAt)
        let latestExplicitRunningAt = max(
            snapshot.inProgressAt,
            snapshot.turnActivityAt,
            snapshot.streamingActivityAt,
            sessionHints?.taskStartedAt ?? 0
        )

        if latestFailureAt > 0,
           now - latestFailureAt <= terminalStatusHold,
           latestFailureAt >= latestCompletionAt,
           latestFailureAt >= latestExplicitRunningAt {
            return .failure
        }

        if latestCompletionAt > 0,
           now - latestCompletionAt >= successSettleDelay,
           now - latestCompletionAt <= terminalStatusHold,
           latestCompletionAt >= latestFailureAt,
           latestCompletionAt >= latestExplicitRunningAt {
            return .success
        }

        if latestExplicitRunningAt > 0,
           now - latestExplicitRunningAt <= runningSignalMaxAge,
           latestExplicitRunningAt >= latestTerminalAt {
            return .running
        }

        // `threads.updated_at` is a weak fallback; it should not suppress a recent terminal state.
        if snapshot.threadUpdatedAt > 0,
           now - snapshot.threadUpdatedAt <= runningSignalMaxAge,
           latestTerminalAt == 0 {
            return .running
        }

        return .idle
    }

    private func fetchRecentThreadSnapshots(limit: Int) -> [LocalCodexThreadSnapshot] {
        fetchRecentThreadReferences(limit: limit).compactMap(makeThreadSnapshot(from:))
    }

    private func fetchRecentThreadReferences(limit: Int) -> [RecentThreadReference] {
        let latestThreadSQL = """
        select id || '|' || updated_at || '|' || source || '|' || cwd
        from threads
        where archived = 0
        order by updated_at desc
        limit \(limit);
        """

        guard
            let latestThreadRows = runSQLiteRows(databaseURL: stateDatabaseURL, sql: latestThreadSQL),
            !latestThreadRows.isEmpty
        else {
            return []
        }

        return latestThreadRows.compactMap(makeThreadReference(from:))
    }

    private func makeThreadReference(from row: String) -> RecentThreadReference? {
        let threadParts = row.split(separator: "|", omittingEmptySubsequences: false)
        guard threadParts.count >= 4 else {
            return nil
        }

        return RecentThreadReference(
            threadID: String(threadParts[0]),
            threadUpdatedAt: TimeInterval(threadParts[1]) ?? 0,
            threadSource: String(threadParts[2]),
            cwd: String(threadParts[3])
        )
    }

    private func makeThreadSnapshot(from reference: RecentThreadReference) -> LocalCodexThreadSnapshot? {
        let threadID = reference.threadID
        let threadUpdatedAt = reference.threadUpdatedAt
        let threadSource = reference.threadSource
        let threadCWD = reference.cwd
        let escapedThreadID = threadID.replacingOccurrences(of: "'", with: "''")
        let logsSQL = """
        select
            coalesce(max(case when feedback_log_body like '%"status":"in_progress"%' then ts end), 0),
            coalesce(max(case when feedback_log_body like '%response.completed%' then ts end), 0),
            coalesce(max(case when feedback_log_body like '%response.failed%' then ts end), 0),
            coalesce(max(case when level in ('ERROR', 'WARN') and (feedback_log_body like '%failed%' or feedback_log_body like '%error%' or feedback_log_body like '%last_error%') then ts end), 0),
            coalesce(max(case when feedback_log_body like '%session_task.turn%' or feedback_log_body like '%submission_dispatch%' then ts end), 0),
            coalesce(max(case
                when feedback_log_body like '%response.output_text.delta%'
                  or feedback_log_body like '%response.function_call_arguments.delta%'
                  or feedback_log_body like '%response.output_item.added%'
                then ts end), 0)
        from logs
        where thread_id = '\(escapedThreadID)';
        """

        guard
            let logRow = runSQLiteQuery(databaseURL: logsDatabaseURL, sql: logsSQL),
            !logRow.isEmpty
        else {
            return LocalCodexThreadSnapshot(
                threadID: threadID,
                threadUpdatedAt: threadUpdatedAt,
                threadSource: threadSource,
                cwd: threadCWD,
                inProgressAt: 0,
                completedAt: 0,
                failedAt: 0,
                turnActivityAt: 0,
                streamingActivityAt: 0
            )
        }

        let logParts = logRow.split(separator: "|", omittingEmptySubsequences: false)
        guard logParts.count == 6 else {
            return LocalCodexThreadSnapshot(
                threadID: threadID,
                threadUpdatedAt: threadUpdatedAt,
                threadSource: threadSource,
                cwd: threadCWD,
                inProgressAt: 0,
                completedAt: 0,
                failedAt: 0,
                turnActivityAt: 0,
                streamingActivityAt: 0
            )
        }

        let explicitFailureAt = TimeInterval(logParts[2]) ?? 0
        let errorFailureAt = TimeInterval(logParts[3]) ?? 0

        return LocalCodexThreadSnapshot(
            threadID: threadID,
            threadUpdatedAt: threadUpdatedAt,
            threadSource: threadSource,
            cwd: threadCWD,
            inProgressAt: TimeInterval(logParts[0]) ?? 0,
            completedAt: TimeInterval(logParts[1]) ?? 0,
            failedAt: max(explicitFailureAt, errorFailureAt),
            turnActivityAt: TimeInterval(logParts[4]) ?? 0,
            streamingActivityAt: TimeInterval(logParts[5]) ?? 0
        )
    }

    private func fetchSessionFileURL(for threadID: String) -> URL? {
        sessionFileLocator.fileURL(for: threadID)
    }

    private func fetchSessionMeta(from fileURL: URL) -> LocalCodexSessionMeta? {
        guard
            let firstLine = readFirstLine(from: fileURL),
            let data = firstLine.data(using: .utf8),
            let record = try? JSONDecoder().decode(LocalCodexSessionMetaRecord.self, from: data)
        else {
            return nil
        }

        return LocalCodexSessionMeta(
            cwd: record.payload.cwd,
            originator: record.payload.originator,
            source: record.payload.source
        )
    }

    private func fetchGlobalState() -> LocalCodexGlobalState? {
        guard
            let data = try? Data(contentsOf: globalStateURL),
            let state = try? JSONDecoder().decode(LocalCodexGlobalState.self, from: data)
        else {
            return nil
        }

        return state
    }

    private func readFirstLine(from fileURL: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return nil
        }

        defer {
            try? handle.close()
        }

        var data = Data()
        while let chunk = try? handle.read(upToCount: 4096), !chunk.isEmpty {
            if let newlineIndex = chunk.firstIndex(of: 0x0A) {
                data.append(chunk.prefix(upTo: newlineIndex))
                break
            }

            data.append(chunk)

            if data.count >= 1_000_000 {
                break
            }
        }

        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func readRecentLines(from fileURL: URL, maxBytes: Int) -> [Substring] {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return []
        }

        defer {
            try? handle.close()
        }

        guard let fileSize = try? handle.seekToEnd(), fileSize > 0 else {
            return []
        }

        let byteCount = UInt64(max(1, maxBytes))
        let startOffset = fileSize > byteCount ? fileSize - byteCount : 0

        do {
            try handle.seek(toOffset: startOffset)
        } catch {
            return []
        }

        guard let data = try? handle.readToEnd(), !data.isEmpty,
              let text = String(data: data, encoding: .utf8) else {
            return []
        }

        let trimmedText: Substring
        if startOffset > 0, let newlineIndex = text.firstIndex(of: "\n") {
            trimmedText = text[text.index(after: newlineIndex)...]
        } else {
            trimmedText = text[...]
        }

        return trimmedText.split(separator: "\n", omittingEmptySubsequences: true)
    }

    private func makeFocusTarget(
        threadID: String,
        sessionMeta: LocalCodexSessionMeta?,
        fallbackSource: String,
        fallbackCWD: String,
        terminalClient: TerminalClient?,
        preferDesktopOrigin: Bool
    ) -> FocusTarget? {
        let resolvedCWD = resolvedWorkingDirectory(sessionMeta: sessionMeta, fallbackCWD: fallbackCWD)
        let clientOrigin: FocusClientOrigin
        if preferDesktopOrigin || sessionMeta?.originator == "Codex Desktop" {
            clientOrigin = .codexDesktop
        } else if sessionMeta?.originator == "codex_cli_rs" || sessionMeta?.source == "cli" || fallbackSource == "cli" {
            clientOrigin = .codexCLI
        } else if sessionMeta?.originator == "codex_vscode" || sessionMeta?.source == "vscode" || fallbackSource == "vscode" {
            clientOrigin = .codexVSCode
        } else {
            clientOrigin = .unknown
        }

        guard clientOrigin != .unknown || !resolvedCWD.isEmpty else {
            return nil
        }

        return FocusTarget(
            clientOrigin: clientOrigin,
            sessionID: threadID,
            displayName: focusTargetLabel(for: clientOrigin, terminalClient: terminalClient),
            cwd: resolvedCWD.isEmpty ? nil : resolvedCWD,
            terminalClient: clientOrigin == .codexCLI ? terminalClient : nil
        )
    }

    private func runSQLiteRows(databaseURL: URL, sql: String) -> [String]? {
        let output = runSQLiteQuery(databaseURL: databaseURL, sql: sql)
        let rows = output?
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init) ?? []
        return rows.isEmpty ? nil : rows
    }

    private func runSQLiteQuery(databaseURL: URL, sql: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [databaseURL.path, "-separator", "|", sql]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func fetchPendingApproval(in fileURL: URL, focusTarget: FocusTarget?) -> ApprovalRequest? {
        let recentLines = readRecentLines(from: fileURL, maxBytes: recentSessionScanBytes)
        guard !recentLines.isEmpty else {
            return nil
        }

        var pendingCalls: [String: PendingApprovalPayload] = [:]

        for line in recentLines {
            guard let data = String(line).data(using: .utf8) else {
                continue
            }

            guard
                let record = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let payload = record["payload"] as? [String: Any],
                let payloadType = payload["type"] as? String
            else {
                continue
            }

            if payloadType == "function_call_output",
               let callID = payload["call_id"] as? String {
                pendingCalls.removeValue(forKey: callID)
                continue
            }

            guard payloadType == "function_call" else {
                continue
            }

            guard
                let callID = payload["call_id"] as? String,
                let argumentString = payload["arguments"] as? String,
                let argumentsData = argumentString.data(using: .utf8),
                let arguments = try? JSONSerialization.jsonObject(with: argumentsData) as? [String: Any],
                let sandboxPermissions = arguments["sandbox_permissions"] as? String,
                sandboxPermissions == "require_escalated"
            else {
                continue
            }

            let timestampString = record["timestamp"] as? String
            let timestamp = timestampString.flatMap(iso8601Formatter.date(from:)) ?? .now
            let command = arguments["command"] as? String ?? ""
            let justification = arguments["justification"] as? String

            pendingCalls[callID] = PendingApprovalPayload(
                callID: callID,
                command: command,
                justification: justification,
                timestamp: timestamp
            )
        }

        guard let latestPending = pendingCalls.values.max(by: { $0.timestamp < $1.timestamp }) else {
            return nil
        }

        return ApprovalRequest(
            id: latestPending.callID,
            commandSummary: summarizeCommand(latestPending.command),
            rationale: latestPending.justification,
            focusTarget: focusTarget,
            createdAt: latestPending.timestamp
        )
    }

    private func summarizeCommand(_ command: String) -> String {
        let singleLine = command
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard singleLine.count > 96 else {
            return singleLine
        }

        return String(singleLine.prefix(96)) + "..."
    }

    private func fetchSessionActivityHints(from fileURL: URL) -> LocalCodexSessionActivityHints? {
        let recentLines = readRecentLines(from: fileURL, maxBytes: recentSessionScanBytes)
        guard !recentLines.isEmpty else {
            return nil
        }

        var taskStartedAt: Date?
        var taskCompletedAt: Date?
        var taskFailedAt: Date?

        for line in recentLines {
            guard let data = String(line).data(using: .utf8) else {
                continue
            }

            guard
                let record = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let payload = record["payload"] as? [String: Any],
                let payloadType = payload["type"] as? String
            else {
                continue
            }

            let timestampString = record["timestamp"] as? String
            let timestamp = timestampString.flatMap(iso8601Formatter.date(from:)) ?? .now

            switch payloadType {
            case "task_started":
                taskStartedAt = timestamp
            case "task_complete", "response.completed":
                taskCompletedAt = timestamp
            case "task_failed", "response.failed":
                taskFailedAt = timestamp
            default:
                continue
            }
        }

        guard taskStartedAt != nil || taskCompletedAt != nil || taskFailedAt != nil else {
            return nil
        }

        return LocalCodexSessionActivityHints(
            taskStartedAt: taskStartedAt?.timeIntervalSince1970 ?? 0,
            taskCompletedAt: taskCompletedAt?.timeIntervalSince1970 ?? 0,
            taskFailedAt: taskFailedAt?.timeIntervalSince1970 ?? 0
        )
    }

    private func fetchFallbackCLISessions(excluding threadIDs: Set<String>) -> [AgentSessionSnapshot] {
        guard isClientRunning(.codexCLI) else {
            return []
        }

        guard let content = try? String(contentsOf: tuiLogURL, encoding: .utf8) else {
            return []
        }

        let now = Date().timeIntervalSince1970
        var snapshots: [String: TUILogThreadSnapshot] = [:]

        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            let stringLine = String(line)
            guard let timestamp = parseLogTimestamp(from: stringLine) else {
                continue
            }

            guard let threadID = extractThreadID(from: stringLine) else {
                continue
            }

            guard !threadIDs.contains(threadID) else {
                continue
            }

            var snapshot = snapshots[threadID] ?? TUILogThreadSnapshot(threadID: threadID)
            snapshot.lastSeenAt = max(snapshot.lastSeenAt, timestamp)

            if stringLine.contains("session_task.turn") {
                snapshot.lastTurnAt = max(snapshot.lastTurnAt, timestamp)
            }

            if stringLine.contains("Shutting down Codex instance")
                || stringLine.contains("op.dispatch.shutdown")
                || (stringLine.contains("session_loop{thread_id=") && stringLine.contains("codex_core::codex: close")) {
                snapshot.shutdownAt = max(snapshot.shutdownAt, timestamp)
            }

            snapshots[threadID] = snapshot
        }

        return snapshots.values.compactMap { snapshot in
            guard now - snapshot.lastSeenAt <= fallbackTUILookback else {
                return nil
            }

            if snapshot.shutdownAt > 0, snapshot.shutdownAt >= snapshot.lastSeenAt {
                return nil
            }

            let activityState: IslandCodexActivityState
            if snapshot.lastTurnAt > 0, now - snapshot.lastTurnAt <= runningSignalMaxAge {
                activityState = .running
            } else {
                activityState = .idle
            }
            let updatedAt = Date(timeIntervalSince1970: snapshot.lastSeenAt)
            let freshness: SessionFreshness
            if activityState == .idle, now - snapshot.lastSeenAt >= staleSessionThreshold {
                freshness = .stale
            } else {
                freshness = .live
            }

            let terminalClient = detectTerminalClient(for: snapshot.threadID)
            let title = "\(terminalClient?.displayName ?? TerminalClient.unknown.displayName) Codex"
            let focusLabel = focusTargetLabel(for: .codexCLI, terminalClient: terminalClient)
            let detail = freshness == .stale
                ? "No recent session updates. The terminal may have been closed."
                : "Watching local Codex CLI session"

            return AgentSessionSnapshot(
                id: snapshot.threadID,
                origin: .codex,
                title: title,
                detail: detail,
                activityState: activityState,
                updatedAt: updatedAt,
                cwd: nil,
                focusTarget: FocusTarget(
                    clientOrigin: .codexCLI,
                    sessionID: snapshot.threadID,
                    displayName: focusLabel,
                    cwd: nil,
                    terminalClient: terminalClient
                ),
                freshness: freshness
            )
        }
    }

    private func sessionTitle(
        sessionMeta: LocalCodexSessionMeta?,
        fallbackSource: String,
        terminalClient: TerminalClient?,
        preferDesktopOrigin: Bool
    ) -> String {
        if sessionMeta?.originator == "codex_cli_rs" || sessionMeta?.source == "cli" || fallbackSource == "cli" {
            return "\(terminalClient?.displayName ?? TerminalClient.unknown.displayName) Codex"
        }

        if preferDesktopOrigin {
            return "Codex Desktop"
        }

        if let sessionMeta {
            return sessionMeta.originDescription
        }

        if fallbackSource == "vscode" {
            return "VS Code Codex"
        }

        return "Local Codex"
    }

    private func focusTargetLabel(for origin: FocusClientOrigin, terminalClient: TerminalClient?) -> String {
        if origin == .codexCLI {
            return "\(terminalClient?.displayName ?? TerminalClient.unknown.displayName) Codex"
        }

        return origin.displayName
    }

    private func shouldRetainIdleSession(
        updatedAt: Date,
        focusTarget: FocusTarget?,
        hasWorkingDirectory: Bool,
        hasActiveWorkspaceMatch: Bool
    ) -> Bool {
        let idleAge = Date().timeIntervalSince(updatedAt)

        if let focusTarget {
            switch focusTarget.clientOrigin {
            case .codexDesktop, .codexVSCode:
                return isClientRunning(focusTarget.clientOrigin)
                    || hasActiveWorkspaceMatch
                    || idleAge <= unconfirmedDesktopSessionLookback
            case .codexCLI, .unknown:
                break
            }
        }

        guard idleAge <= idleSessionLookback else {
            return false
        }

        if hasWorkingDirectory {
            return true
        }

        guard let focusTarget else {
            return false
        }

        switch focusTarget.clientOrigin {
        case .codexCLI:
            return isClientRunning(.codexCLI)
        case .codexDesktop, .codexVSCode:
            return isClientRunning(focusTarget.clientOrigin) || hasActiveWorkspaceMatch
        case .unknown:
            return true
        }
    }

    private func hasActiveWorkspaceMatch(cwd: String, globalState: LocalCodexGlobalState?) -> Bool {
        let normalizedCWD = cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedCWD.isEmpty else {
            return false
        }

        return globalState?.activeWorkspaceRoots.contains(where: { root in
            normalizedCWD == root || normalizedCWD.hasPrefix(root + "/")
        }) ?? false
    }

    private func resolvedWorkingDirectory(sessionMeta: LocalCodexSessionMeta?, threadSnapshot: LocalCodexThreadSnapshot) -> String {
        resolvedWorkingDirectory(sessionMeta: sessionMeta, fallbackCWD: threadSnapshot.cwd)
    }

    private func resolvedWorkingDirectory(sessionMeta: LocalCodexSessionMeta?, fallbackCWD: String) -> String {
        let primaryCWD = sessionMeta?.cwd.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !primaryCWD.isEmpty {
            return primaryCWD
        }

        return fallbackCWD.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sessionFreshness(
        activityState: IslandCodexActivityState,
        updatedAt: Date,
        focusTarget: FocusTarget?
    ) -> SessionFreshness {
        guard activityState == .idle else {
            return .live
        }

        guard Date().timeIntervalSince(updatedAt) >= staleSessionThreshold else {
            return .live
        }

        guard focusTarget?.clientOrigin == .codexCLI else {
            return .live
        }

        return .stale
    }

    private func detectTerminalClient(for threadID: String) -> TerminalClient? {
        guard let shellSnapshotURL = latestShellSnapshotURL(for: threadID),
              let shellSnapshot = try? String(contentsOf: shellSnapshotURL, encoding: .utf8) else {
            return nil
        }

        if shellSnapshot.contains("export TERM_PROGRAM=WarpTerminal")
            || shellSnapshot.contains("export WARP_IS_LOCAL_SHELL_SESSION=1") {
            return .warp
        }

        if shellSnapshot.contains("export TERM_PROGRAM=iTerm.app")
            || shellSnapshot.contains("export ITERM_SESSION_ID=") {
            return .iTerm
        }

        if shellSnapshot.contains("export TERM_PROGRAM=Apple_Terminal")
            || shellSnapshot.contains("export TERM_SESSION_ID=") {
            return .terminal
        }

        if shellSnapshot.contains("export TERM_PROGRAM=WezTerm")
            || shellSnapshot.contains("export WEZTERM_EXECUTABLE=") {
            return .wezTerm
        }

        if shellSnapshot.contains("export TERM_PROGRAM=ghostty")
            || shellSnapshot.contains("export GHOSTTY_RESOURCES_DIR=") {
            return .ghostty
        }

        if shellSnapshot.contains("export TERM_PROGRAM=Alacritty")
            || shellSnapshot.contains("export ALACRITTY_SOCKET=") {
            return .alacritty
        }

        return nil
    }

    private func latestShellSnapshotURL(for threadID: String) -> URL? {
        guard let fileURLs = try? FileManager.default.contentsOfDirectory(
            at: shellSnapshotsDirectoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        return fileURLs
            .filter { $0.lastPathComponent.hasPrefix(threadID + ".") && $0.pathExtension == "sh" }
            .max { lhs, rhs in
                let leftDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rightDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return leftDate < rightDate
            }
    }

    private func parseLogTimestamp(from line: String) -> TimeInterval? {
        guard let timestampEnd = line.firstIndex(of: " ") else {
            return nil
        }

        let timestampString = String(line[..<timestampEnd])
        return iso8601Formatter.date(from: timestampString)?.timeIntervalSince1970
    }

    private func extractThreadID(from line: String) -> String? {
        guard let startRange = line.range(of: "thread_id=") else {
            return nil
        }

        let suffix = line[startRange.upperBound...]
        let threadID = suffix.prefix { character in
            character.isLetter || character.isNumber || character == "-"
        }

        return threadID.isEmpty ? nil : String(threadID)
    }

    private func isClientRunning(_ origin: FocusClientOrigin) -> Bool {
        let bundleIdentifiers: [String]
        switch origin {
        case .codexDesktop:
            bundleIdentifiers = ["com.openai.codex"]
        case .codexVSCode:
            bundleIdentifiers = ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.todesktop.230313mzl4w4u92"]
        case .codexCLI:
            bundleIdentifiers = ["com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.github.wez.wezterm", "com.mitchellh.ghostty", "org.alacritty"]
        case .unknown:
            bundleIdentifiers = []
        }

        guard !bundleIdentifiers.isEmpty else {
            return false
        }

        return NSWorkspace.shared.runningApplications.contains { application in
            guard let bundleIdentifier = application.bundleIdentifier else {
                return false
            }
            return bundleIdentifiers.contains(bundleIdentifier)
        }
    }
}

private final class SessionFileLocator: @unchecked Sendable {
    private let rootURL: URL
    private let searchLookbackDays = 45
    private let lock = NSLock()
    private var cache: [String: URL] = [:]

    init(rootURL: URL) {
        self.rootURL = rootURL
    }

    func fileURL(for threadID: String) -> URL? {
        lock.lock()
        if let cachedURL = cache[threadID], FileManager.default.fileExists(atPath: cachedURL.path) {
            lock.unlock()
            return cachedURL
        }
        lock.unlock()

        let resolvedURL = searchRecentDays(for: threadID)

        lock.lock()
        cache[threadID] = resolvedURL
        lock.unlock()

        return resolvedURL
    }

    private func searchRecentDays(for threadID: String) -> URL? {
        let calendar = Calendar.current
        let candidateDates = (0 ..< searchLookbackDays).compactMap { dayOffset -> Date? in
            calendar.date(byAdding: .day, value: -dayOffset, to: .now)
        }

        for date in candidateDates {
            let components = calendar.dateComponents([.year, .month, .day], from: date)
            guard
                let year = components.year,
                let month = components.month,
                let day = components.day
            else {
                continue
            }

            let dayDirectory = rootURL
                .appendingPathComponent(String(format: "%04d", year))
                .appendingPathComponent(String(format: "%02d", month))
                .appendingPathComponent(String(format: "%02d", day))

            guard let fileURLs = try? FileManager.default.contentsOfDirectory(
                at: dayDirectory,
                includingPropertiesForKeys: nil
            ) else {
                continue
            }

            if let matchingFileURL = fileURLs.first(where: {
                $0.pathExtension == "jsonl" && $0.lastPathComponent.contains(threadID)
            }) {
                return matchingFileURL
            }
        }

        return nil
    }
}

private struct LocalCodexThreadSnapshot {
    let threadID: String
    let threadUpdatedAt: TimeInterval
    let threadSource: String
    let cwd: String
    let inProgressAt: TimeInterval
    let completedAt: TimeInterval
    let failedAt: TimeInterval
    let turnActivityAt: TimeInterval
    let streamingActivityAt: TimeInterval
}

private struct RecentThreadReference {
    let threadID: String
    let threadUpdatedAt: TimeInterval
    let threadSource: String
    let cwd: String
}

private struct LocalCodexSessionMeta {
    let cwd: String
    let originator: String
    let source: String

    var originDescription: String {
        if originator == "Codex Desktop" {
            return "Codex Desktop"
        }
        if originator == "codex_cli_rs" || source == "cli" {
            return "Terminal Codex"
        }
        if originator == "codex_vscode" || source == "vscode" {
            return "VS Code Codex"
        }
        return "Local Codex"
    }
}

private struct LocalCodexSessionMetaRecord: Decodable {
    struct Payload: Decodable {
        let cwd: String
        let originator: String
        let source: String
    }

    let payload: Payload
}

private struct LocalCodexGlobalState: Decodable {
    let activeWorkspaceRoots: [String]

    private enum CodingKeys: String, CodingKey {
        case activeWorkspaceRoots = "active-workspace-roots"
    }
}

private struct PendingApprovalPayload {
    let callID: String
    let command: String
    let justification: String?
    let timestamp: Date
}

private struct LocalCodexSessionActivityHints {
    let taskStartedAt: TimeInterval
    let taskCompletedAt: TimeInterval
    let taskFailedAt: TimeInterval

    var latestKnownAt: TimeInterval {
        max(taskStartedAt, taskCompletedAt, taskFailedAt)
    }
}

private struct TUILogThreadSnapshot {
    let threadID: String
    var lastSeenAt: TimeInterval = 0
    var lastTurnAt: TimeInterval = 0
    var shutdownAt: TimeInterval = 0
}
