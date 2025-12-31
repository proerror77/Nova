import SwiftUI

// MARK: - Streaming Indicator

/// Visual indicator showing AI is generating a response
struct StreamingIndicator: View {

    // MARK: - Style

    enum Style {
        case dots       // Animated bouncing dots
        case pulse      // Pulsing circle
        case wave       // Wave animation bars
        case thinking   // "Thinking..." text with animation
        case typing     // Typing dots like messaging apps
    }

    // MARK: - Properties

    let style: Style
    var color: Color = .accentColor
    var size: CGFloat = 8

    // MARK: - Body

    var body: some View {
        switch style {
        case .dots:
            DotsIndicator(color: color, size: size)
        case .pulse:
            pulseIndicator
        case .wave:
            WaveIndicator(color: color, size: size)
        case .thinking:
            ThinkingIndicator(color: color, size: size)
        case .typing:
            TypingIndicator(color: color, size: size)
        }
    }

    // MARK: - Pulse Animation (uses repeatForever - safe)

    private var pulseIndicator: some View {
        PulseIndicator(color: color, size: size)
    }
}

// MARK: - Dots Indicator (TimelineView based - auto cleanup)

private struct DotsIndicator: View {
    let color: Color
    let size: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.3)) { timeline in
            let phase = Int(timeline.date.timeIntervalSinceReferenceDate / 0.3) % 3
            HStack(spacing: size * 0.5) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(color)
                        .frame(width: size, height: size)
                        .scaleEffect(phase == index ? 1.3 : 0.8)
                        .opacity(phase == index ? 1 : 0.5)
                        .animation(.easeInOut(duration: 0.2), value: phase)
                }
            }
        }
    }
}

// MARK: - Pulse Indicator (repeatForever - safe)

private struct PulseIndicator: View {
    let color: Color
    let size: CGFloat
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.3))
                .frame(width: size * 2.5, height: size * 2.5)
                .scaleEffect(isAnimating ? 1.3 : 1)
                .opacity(isAnimating ? 0.5 : 1)

            Circle()
                .fill(color)
                .frame(width: size * 1.5, height: size * 1.5)
        }
        .onAppear {
            withAnimation(
                Animation.easeInOut(duration: 0.8)
                    .repeatForever(autoreverses: true)
            ) {
                isAnimating = true
            }
        }
    }
}

// MARK: - Wave Indicator (TimelineView based - auto cleanup)

private struct WaveIndicator: View {
    let color: Color
    let size: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1)) { timeline in
            let phase = Int(timeline.date.timeIntervalSinceReferenceDate / 0.1)
            HStack(spacing: size * 0.3) {
                ForEach(0..<5, id: \.self) { index in
                    RoundedRectangle(cornerRadius: size * 0.2)
                        .fill(color)
                        .frame(width: size * 0.4, height: waveHeight(for: index, phase: phase))
                        .animation(.easeInOut(duration: 0.1), value: phase)
                }
            }
        }
    }

    private func waveHeight(for index: Int, phase: Int) -> CGFloat {
        let baseHeight = size
        let maxHeight = size * 2.5
        let phaseValue = Double(phase + index) * 0.2
        let normalized = (sin(phaseValue * .pi) + 1) / 2
        return baseHeight + (maxHeight - baseHeight) * normalized
    }
}

// MARK: - Thinking Indicator (TimelineView based - auto cleanup)

private struct ThinkingIndicator: View {
    let color: Color
    let size: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.4)) { timeline in
            let phase = Int(timeline.date.timeIntervalSinceReferenceDate / 0.4) % 4
            HStack(spacing: 4) {
                Text("Thinking")
                    .font(.system(size: size * 1.5, weight: .medium))
                    .foregroundColor(color)

                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { index in
                        Text(".")
                            .font(.system(size: size * 1.75, weight: .bold))
                            .foregroundColor(color)
                            .opacity(phase > index ? 1 : 0.3)
                            .animation(.easeInOut(duration: 0.2), value: phase)
                    }
                }
            }
        }
    }
}

// MARK: - Typing Indicator (TimelineView based - auto cleanup)

private struct TypingIndicator: View {
    let color: Color
    let size: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.15)) { timeline in
            let phase = Int(timeline.date.timeIntervalSinceReferenceDate / 0.15)
            HStack(spacing: size * 0.6) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(color)
                        .frame(width: size, height: size)
                        .offset(y: typingOffset(for: index, phase: phase))
                        .animation(.easeInOut(duration: 0.15), value: phase)
                }
            }
        }
    }

    private func typingOffset(for index: Int, phase: Int) -> CGFloat {
        let currentPhase = (phase + index) % 6
        switch currentPhase {
        case 0, 1:
            return -size * 0.5
        case 2, 3:
            return 0
        default:
            return size * 0.3
        }
    }
}

// MARK: - AI Thinking Bubble

/// A chat bubble style indicator showing AI is thinking
struct AIThinkingBubble: View {

    var color: Color = .secondary.opacity(0.2)
    var indicatorColor: Color = .secondary

    var body: some View {
        HStack(spacing: 8) {
            StreamingIndicator(style: .typing, color: indicatorColor, size: 6)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(color)
        )
    }
}

// MARK: - Previews

#Preview("Streaming Indicators") {
    VStack(spacing: 30) {
        HStack(spacing: 40) {
            VStack {
                StreamingIndicator(style: .dots)
                Text("Dots").font(.caption)
            }

            VStack {
                StreamingIndicator(style: .pulse)
                Text("Pulse").font(.caption)
            }

            VStack {
                StreamingIndicator(style: .wave)
                Text("Wave").font(.caption)
            }
        }

        HStack(spacing: 40) {
            VStack {
                StreamingIndicator(style: .thinking)
                Text("Thinking").font(.caption)
            }

            VStack {
                StreamingIndicator(style: .typing)
                Text("Typing").font(.caption)
            }
        }

        AIThinkingBubble()
    }
    .padding()
}
