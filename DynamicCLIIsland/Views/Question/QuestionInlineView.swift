import SwiftUI

struct QuestionInlineView: View {
    @ObservedObject var store: ProgressStore
    let prompt: ClaudeQuestionPrompt
    let header: AnyView
    let timestampText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                header
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                headerRow
                    .padding(.horizontal, 32)
            }
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(chromeBackground)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.white.opacity(0.05))
                    .frame(height: 1)
            }
            .zIndex(1)

            QuestionPromptCardView(
                prompt: prompt,
                questionStore: store.questionInputStore,
                timestampText: timestampText,
                onSubmit: store.submitQuestionAnswer,
                onDismiss: store.dismissQuestionPrompt,
                pinsActions: true,
                fillsAvailableHeight: true
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 32)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(chromeBackground)
    }

    private var focusTarget: FocusTarget? {
        store.sessions.first(where: {
            $0.id == prompt.sessionID || $0.focusTarget?.sessionID == prompt.sessionID
        })?.focusTarget
    }

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accentGreen)

                Text("Claude Needs Input")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(red: 0.10, green: 0.15, blue: 0.13))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(accentGreen.opacity(0.22), lineWidth: 1)
            )

            if !store.questionInputStore.supportsSubmission {
                Text("Mirror Only")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color(red: 0.78, green: 0.86, blue: 0.83))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color(red: 0.11, green: 0.13, blue: 0.13))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            }

            Spacer(minLength: 8)

            if let focusTarget = focusTarget {
                Button(action: { store.bringForward(focusTarget) }) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 10, weight: .semibold))

                        Text("Open")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(Color.white.opacity(0.84))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var chromeBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.08, green: 0.10, blue: 0.10),
                Color(red: 0.05, green: 0.06, blue: 0.06)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var accentGreen: Color {
        Color(red: 0.42, green: 0.90, blue: 0.68)
    }
}
