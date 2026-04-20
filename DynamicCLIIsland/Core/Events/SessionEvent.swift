//
//  SessionEvent.swift
//  HermitFlow
//
//  Phase 4 event model.
//

import Foundation

struct SessionEvent: Hashable, Identifiable {
    let id: String
    let origin: SessionOrigin
    let title: String
    let detail: String
    let activityState: IslandCodexActivityState
    let runningDetail: IslandRunningDetail?
    let updatedAt: Date
    let cwd: String?
    let focusTarget: FocusTarget?
    let freshness: SessionFreshness

    init(snapshot: AgentSessionSnapshot) {
        id = snapshot.id
        origin = snapshot.origin
        title = snapshot.title
        detail = snapshot.detail
        activityState = snapshot.activityState
        runningDetail = snapshot.runningDetail
        updatedAt = snapshot.updatedAt
        cwd = snapshot.cwd
        focusTarget = snapshot.focusTarget
        freshness = snapshot.freshness
    }

    init(
        id: String,
        origin: SessionOrigin,
        title: String,
        detail: String,
        activityState: IslandCodexActivityState,
        runningDetail: IslandRunningDetail?,
        updatedAt: Date,
        cwd: String?,
        focusTarget: FocusTarget?,
        freshness: SessionFreshness
    ) {
        self.id = id
        self.origin = origin
        self.title = title
        self.detail = detail
        self.activityState = activityState
        self.runningDetail = runningDetail
        self.updatedAt = updatedAt
        self.cwd = cwd
        self.focusTarget = focusTarget
        self.freshness = freshness
    }

    var snapshot: AgentSessionSnapshot {
        AgentSessionSnapshot(
            id: id,
            origin: origin,
            title: title,
            detail: detail,
            activityState: activityState,
            runningDetail: runningDetail,
            updatedAt: updatedAt,
            cwd: cwd,
            focusTarget: focusTarget,
            freshness: freshness
        )
    }
}
