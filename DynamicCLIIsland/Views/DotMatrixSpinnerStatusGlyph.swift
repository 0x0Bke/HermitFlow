import SwiftUI

struct DotMatrixSpinnerStatusGlyph: View {
    let isAnimating: Bool

    private let cycleDuration: Double = 1.0
    private let riseDuration: Double = 0.12
    private let fallDuration: Double = 0.48
    private let dotSize: CGFloat = 4.6
    private let dotSpacing: CGFloat = 0
    private let restingColor = Color(.sRGB, red: 51 / 255, green: 51 / 255, blue: 51 / 255, opacity: 1)
    private let activeColor = Color(.sRGB, red: 1.0, green: 118 / 255, blue: 5 / 255, opacity: 1)
    private let glowColor = Color(.sRGB, red: 1.0, green: 205 / 255, blue: 163 / 255, opacity: 1)

    private let orbitPhases: [Int: Double] = [
        1: 0.00,
        5: 0.12,
        7: 0.32,
        3: 0.52
    ]

    var body: some View {
        Group {
            if isAnimating {
                TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { timeline in
                    glyphBody(at: normalizedPhase(for: timeline.date))
                }
            } else {
                glyphBody(at: nil)
            }
        }
        .frame(width: 16.5, height: 16.5)
    }

    private func glyphBody(at phase: Double?) -> some View {
        VStack(spacing: dotSpacing) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: dotSpacing) {
                    ForEach(0..<3, id: \.self) { column in
                        let index = row * 3 + column
                        let intensity = dotIntensity(for: index, phase: phase)

                        RoundedRectangle(cornerRadius: 0.4, style: .continuous)
                            .fill(dotFill(intensity: intensity))
                            .frame(width: dotSize, height: dotSize)
                            .scaleEffect(1 + intensity * 0.1)
                            .shadow(color: glowColor.opacity(intensity * 0.68), radius: 0.9 + intensity * 2.3)
                    }
                }
            }
        }
        .drawingGroup(opaque: false, colorMode: .linear)
    }

    private func normalizedPhase(for date: Date) -> Double {
        let elapsed = date.timeIntervalSinceReferenceDate
        return elapsed.truncatingRemainder(dividingBy: cycleDuration) / cycleDuration
    }

    private func dotIntensity(for index: Int, phase: Double?) -> Double {
        if index == 4 {
            return 1
        }

        guard let phase, let peak = orbitPhases[index] else {
            return index == 1 ? 1 : 0
        }

        let riseStart = wrappedUnit(peak - riseDuration / cycleDuration)
        if phaseIsWithinInterval(phase, start: riseStart, end: peak) {
            let progress = intervalProgress(value: phase, start: riseStart, end: peak)
            return smoothStep(progress)
        }

        let fallEnd = wrappedUnit(peak + fallDuration / cycleDuration)
        if phaseIsWithinInterval(phase, start: peak, end: fallEnd) {
            let progress = intervalProgress(value: phase, start: peak, end: fallEnd)
            return 1 - smoothStep(progress)
        }

        return 0
    }

    private func dotFill(intensity: Double) -> some ShapeStyle {
        let baseColor = intensity > 0 ? activeColor : restingColor
        return baseColor.opacity(intensity > 0 ? 0.5 + intensity * 0.5 : 1)
    }

    private func wrappedUnit(_ value: Double) -> Double {
        let wrapped = value.truncatingRemainder(dividingBy: 1)
        return wrapped >= 0 ? wrapped : wrapped + 1
    }

    private func phaseIsWithinInterval(_ value: Double, start: Double, end: Double) -> Bool {
        if start <= end {
            return value >= start && value <= end
        }

        return value >= start || value <= end
    }

    private func intervalProgress(value: Double, start: Double, end: Double) -> Double {
        let adjustedEnd = end >= start ? end : end + 1
        let adjustedValue = value >= start ? value : value + 1
        let duration = max(adjustedEnd - start, .leastNonzeroMagnitude)
        return min(max((adjustedValue - start) / duration, 0), 1)
    }

    private func smoothStep(_ value: Double) -> Double {
        let clamped = min(max(value, 0), 1)
        return clamped * clamped * clamped * (clamped * (clamped * 6 - 15) + 10)
    }
}
