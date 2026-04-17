import SwiftUI

struct QuestionOptionButtonsView: View {
    let options: [QuestionOption]
    let selectedOptionID: String?
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(options) { option in
                Button(action: { onSelect(option.id) }) {
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: selectedOptionID == option.id ? "largecircle.fill.circle" : "circle")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(selectedOptionID == option.id ? accentGreen : Color.white.opacity(0.32))
                            .padding(.top, 1)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(option.title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            if let detail = option.detail, !detail.isEmpty {
                                Text(detail)
                                    .font(.system(size: 10, weight: .regular))
                                    .foregroundStyle(Color.white.opacity(0.50))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(selectedOptionID == option.id ? Color(red: 0.10, green: 0.16, blue: 0.14) : Color(red: 0.11, green: 0.12, blue: 0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(selectedOptionID == option.id ? accentGreen.opacity(0.28) : Color.white.opacity(0.05), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var accentGreen: Color {
        Color(red: 0.42, green: 0.90, blue: 0.68)
    }
}
