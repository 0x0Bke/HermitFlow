import SwiftUI

struct QuestionPromptCardView: View {
    let prompt: ClaudeQuestionPrompt
    @ObservedObject var questionStore: QuestionStore
    let timestampText: String
    let onSubmit: () -> Void
    let onDismiss: () -> Void
    var pinsActions = false
    var fillsAvailableHeight = false

    var body: some View {
        Group {
            if pinsActions {
                pinnedLayout
            } else {
                regularLayout
            }
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: fillsAvailableHeight ? .infinity : nil,
            alignment: .topLeading
        )
        .background(cardBackground)
        .clipShape(cardShape)
        .overlay(cardBorder)
    }

    private var regularLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            contentSections
            actionBar
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var pinnedLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.vertical, showsIndicators: true) {
                contentSections
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color.white.opacity(0.05))
                    .frame(height: 1)

                actionBar
                    .padding(12)
                    .background(footerBackground)
            }
        }
    }

    private var contentSections: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let headerPromptText {
                Text(headerPromptText)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if showsBodyDivider {
                bodyDivider
            }

            if prompt.hasOptions {
                VStack(alignment: .leading, spacing: 7) {
                    sectionHeader(title: "Choices", systemImage: "list.bullet")

                    QuestionOptionButtonsView(
                        options: prompt.options,
                        selectedOptionID: questionStore.selectedOptionID,
                        onSelect: questionStore.selectOption(id:)
                    )
                }
            }

            if prompt.allowsFreeText {
                QuestionTextInputView(prompt: prompt, questionStore: questionStore)
            }

            if let errorMessage = questionStore.errorMessage, !errorMessage.isEmpty {
                compactNotice(
                    text: errorMessage,
                    systemImage: "exclamationmark.triangle.fill",
                    tint: Color(red: 1.0, green: 0.48, blue: 0.46),
                    fill: Color(red: 0.16, green: 0.09, blue: 0.09)
                )
            }

            if !questionStore.supportsSubmission {
                compactNotice(
                    text: "Answer in Claude CLI or the Claude extension. HermitFlow is mirroring this prompt only.",
                    systemImage: "arrow.triangle.branch",
                    tint: accentGreen,
                    fill: Color(red: 0.09, green: 0.11, blue: 0.11)
                )
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            Button(action: onDismiss) {
                Text("Cancel")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.84))
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.07), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            Button(action: onSubmit) {
                HStack(spacing: 6) {
                    if questionStore.isSubmitting {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    }

                    Text(questionStore.supportsSubmission ? "Send Answer" : "Answer In Claude")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(primaryButtonFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(primaryButtonStroke, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(!questionStore.canSubmit() || questionStore.isSubmitting)
        }
    }

    private var cardBackground: some View {
        cardShape
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.08, green: 0.12, blue: 0.11),
                        Color(red: 0.05, green: 0.07, blue: 0.07)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    private var cardBorder: some View {
        cardShape
            .stroke(accentGreen.opacity(0.16), lineWidth: 1)
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
    }

    private var footerBackground: some View {
        Color(red: 0.05, green: 0.07, blue: 0.07)
    }

    private var headerPromptText: String? {
        if let message = prompt.message?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty {
            return message
        }

        let title = prompt.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            return title
        }

        if let detail = prompt.detail?.trimmingCharacters(in: .whitespacesAndNewlines), !detail.isEmpty {
            return detail
        }

        return nil
    }

    private var hasSecondaryContent: Bool {
        prompt.hasOptions
            || prompt.allowsFreeText
            || (questionStore.errorMessage?.isEmpty == false)
            || !questionStore.supportsSubmission
    }

    private var showsBodyDivider: Bool {
        headerPromptText != nil && hasSecondaryContent
    }

    private var accentGreen: Color {
        Color(red: 0.42, green: 0.90, blue: 0.68)
    }

    private var primaryButtonFill: AnyShapeStyle {
        if questionStore.canSubmit() {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color(red: 0.19, green: 0.83, blue: 0.50),
                        Color(red: 0.11, green: 0.67, blue: 0.40)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }

        return AnyShapeStyle(Color(red: 0.14, green: 0.16, blue: 0.16))
    }

    private var primaryButtonStroke: Color {
        questionStore.canSubmit() ? accentGreen.opacity(0.24) : Color.white.opacity(0.06)
    }

    private var bodyDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.05))
            .frame(height: 1)
    }

    private func sectionHeader(
        title: String,
        systemImage: String
    ) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(accentGreen)

            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.60))
        }
    }

    private func compactNotice(
        text: String,
        systemImage: String,
        tint: Color,
        fill: Color
    ) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .padding(.top, 1)

            Text(text)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.76))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        )
    }
}
