import Foundation

struct ExternalProgressFileSource {
    func loadEnvelope(from url: URL, using decoder: JSONDecoder) throws -> ProgressEnvelope {
        let data = try Data(contentsOf: url)
        return try decoder.decode(ProgressEnvelope.self, from: data)
    }
}

struct DemoProgressSource {
    func makeInitialTasks(now: Date = .now) -> [CLIJob] {
        [
            CLIJob(
                id: "codex-refactor",
                provider: .codex,
                title: "Refactor agent pipeline",
                detail: "Analyzing repo, editing Swift files, validating build graph",
                progress: 0.41,
                stage: .running,
                etaSeconds: 182,
                updatedAt: now
            ),
            CLIJob(
                id: "claude-spec",
                provider: .claude,
                title: "Spec draft for onboarding flow",
                detail: "Summarizing edge cases and implementation notes",
                progress: 0.24,
                stage: .running,
                etaSeconds: 228,
                updatedAt: now.addingTimeInterval(-15)
            ),
            CLIJob(
                id: "cli-tests",
                provider: .generic,
                title: "Regression test sweep",
                detail: "Queued after active edits finish",
                progress: 0,
                stage: .queued,
                etaSeconds: nil,
                updatedAt: now.addingTimeInterval(-40)
            )
        ]
    }

    func advance(_ tasks: [CLIJob], now: Date = .now) -> [CLIJob] {
        guard !tasks.isEmpty else {
            return makeInitialTasks(now: now)
        }

        var updated = tasks
        for index in updated.indices {
            switch updated[index].stage {
            case .queued:
                updated[index].stage = .running
                updated[index].progress = 0.08
                updated[index].etaSeconds = 280
            case .running:
                updated[index].progress += Double.random(in: 0.03 ... 0.08)
                if updated[index].progress >= 1 {
                    updated[index].progress = 1
                    updated[index].stage = .success
                    updated[index].etaSeconds = nil
                } else {
                    let remaining = Int((1 - updated[index].progress) * 300)
                    updated[index].etaSeconds = max(remaining, 14)
                }
            case .blocked:
                updated[index].stage = .running
                updated[index].etaSeconds = 120
            case .success, .failed:
                break
            }

            updated[index].updatedAt = now
        }

        if updated.allSatisfy({ $0.stage == .success }) {
            return makeInitialTasks(now: now)
        }

        return updated
    }
}
