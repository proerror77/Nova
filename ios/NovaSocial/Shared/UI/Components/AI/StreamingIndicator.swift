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

    @State private var animationPhase: Int = 0

    // MARK: - Body

    var body: some View {
        switch style {
        case .dots:
            dotsIndicator
        case .pulse:
            pulseIndicator
        case .wave:
            waveIndicator
        case .thinking:
            thinkingIndicator
        case .typing:
            typingIndicator
        }
    }

    // MARK: - Dots Animation

    private var dotsIndicator: some View {
        HStack(spacing: size * 0.5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(color)
                    .frame(width: size, height: size)
                    .scaleEffect(animationPhase == index ? 1.3 : 0.8)
                    .opacity(animationPhase == index ? 1 : 0.5)
            }
        }
        .onAppear {
            startDotsAnimation()
        }
    }

    private func startDotsAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                animationPhase = (animationPhase + 1) % 3
            }
        }
    }

    // MARK: - Pulse Animation

    private var pulseIndicator: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.3))
                .frame(width: size * 2.5, height: size * 2.5)
                .scaleEffect(animationPhase == 1 ? 1.3 : 1)
                .opacity(animationPhase == 1 ? 0.5 : 1)

            Circle()
                .fill(color)
                .frame(width: size * 1.5, height: size * 1.5)
        }
        .onAppear {
            withAnimation(
                Animation.easeInOut(duration: 0.8)
                    .repeatForever(autoreverses: true)
            ) {
                animationPhase = 1
            }
        }
    }

    // MARK: - Wave Animation

    private var waveIndicator: some View {
        HStack(spacing: size * 0.3) {
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: size * 0.2)
                    .fill(color)
                    .frame(width: size * 0.4, height: waveHeight(for: index))
            }
        }
        .onAppear {
            startWaveAnimation()
        }
    }

    private func waveHeight(for index: Int) -> CGFloat {
        let baseHeight = size
        let maxHeight = size * 2.5
        let phase = Double(animationPhase + index) * 0.2
        let normalized = (sin(phase * .pi) + 1) / 2
        return baseHeight + (maxHeight - baseHeight) * normalized
    }

    private func startWaveAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.1)) {
                animationPhase += 1
            }
        }
    }

    // MARK: - Thinking Animation

    private var thinkingIndicator: some View {
        HStack(spacing: 4) {
            Text("Thinking")
                .font(.system(size: size * 1.5, weight: .medium))
                .foregroundColor(color)

            HStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { index in
                    Text(".")
                        .font(.system(size: size * 1.75, weight: .bold))
                        .foregroundColor(color)
                        .opacity(animationPhase > index ? 1 : 0.3)
                }
            }
        }
        .onAppear {
            startThinkingAnimation()
        }
    }

    private func startThinkingAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                animationPhase = (animationPhase + 1) % 4
            }
        }
    }

    // MARK: - Typing Animation

    private var typingIndicator: some View {
        HStack(spacing: size * 0.6) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(color)
                    .frame(width: size, height: size)
                    .offset(y: typingOffset(for: index))
            }
        }
        .onAppear {
            startTypingAnimation()
        }
    }

    private func typingOffset(for index: Int) -> CGFloat {
        let phase = (animationPhase + index) % 6
        switch phase {
        case 0, 1:
            return -size * 0.5
        case 2, 3:
            return 0
        default:
            return size * 0.3
        }
    }

    private func startTypingAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.15)) {
                animationPhase += 1
            }
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
