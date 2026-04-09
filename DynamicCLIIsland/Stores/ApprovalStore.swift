import Foundation

final class ApprovalStore {
    private(set) var currentRequest: ApprovalRequest?
    private var lastObservedAt: Date?
    private let retentionWindow: TimeInterval = 1.25
    private var resolvedRequestIDs: Set<String> = []

    func update(with request: ApprovalRequest?) {
        let now = Date()

        if let request {
            guard !resolvedRequestIDs.contains(request.id) else {
                return
            }

            currentRequest = request
            lastObservedAt = now
            return
        }

        if currentRequest?.source == .claude {
            clear()
            return
        }

        if let currentRequest, resolvedRequestIDs.contains(currentRequest.id) {
            clearCurrentRequest()
            return
        }

        if currentRequest?.source == .codex {
            return
        }

        guard
            currentRequest != nil,
            let lastObservedAt,
            now.timeIntervalSince(lastObservedAt) <= retentionWindow
        else {
            clearCurrentRequest()
            return
        }
    }

    func markResolved(id: String) {
        resolvedRequestIDs.insert(id)

        if currentRequest?.id == id {
            clearCurrentRequest()
        }
    }

    func markResolved(ids: some Sequence<String>) {
        for id in ids {
            resolvedRequestIDs.insert(id)
        }

        if let currentRequest, resolvedRequestIDs.contains(currentRequest.id) {
            clearCurrentRequest()
        }
    }

    func clear() {
        resolvedRequestIDs.removeAll()
        clearCurrentRequest()
    }

    func isResolved(id: String) -> Bool {
        resolvedRequestIDs.contains(id)
    }

    private func clearCurrentRequest() {
        currentRequest = nil
        lastObservedAt = nil
    }
}
