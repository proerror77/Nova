import SwiftUI

// MARK: - Streaming Text View

/// Displays streaming text with typewriter effect and cursor animation
struct StreamingTextView: View {

    // MARK: - Properties

    let text: String
    let isStreaming: Bool
    var textStyle: Font = .body
    var textColor: Color = .primary
    var cursorColor: Color = .accentColor

    @State private var showCursor: Bool = true

    // MARK: - Body

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            Text(text)
                .font(textStyle)
                .foregroundColor(textColor)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            if isStreaming {
                StreamingCursor(color: cursorColor)
            }
        }
    }
}

// MARK: - Streaming Cursor

/// Animated blinking cursor for streaming text
struct StreamingCursor: View {

    var color: Color = .accentColor
    var width: CGFloat = 2
    var height: CGFloat = 16

    @State private var isVisible: Bool = true

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: width, height: height)
            .opacity(isVisible ? 1 : 0)
            .animation(
                Animation.easeInOut(duration: 0.5)
                    .repeatForever(autoreverses: true),
                value: isVisible
            )
            .onAppear {
                isVisible = true
            }
    }
}

// MARK: - Typewriter Text View

/// Displays text with a typewriter animation effect
struct TypewriterTextView: View {

    let fullText: String
    var typingSpeed: TimeInterval = 0.03
    var textStyle: Font = .body
    var textColor: Color = .primary

    @State private var displayedText: String = ""
    @State private var currentIndex: Int = 0

    var body: some View {
        Text(displayedText)
            .font(textStyle)
            .foregroundColor(textColor)
            .fixedSize(horizontal: false, vertical: true)
            .onAppear {
                startTyping()
            }
            .onChange(of: fullText) { _, newValue in
                // If text changed, update displayed text incrementally
                if newValue.hasPrefix(displayedText) {
                    // New text is an extension of current text
                    let remaining = String(newValue.dropFirst(displayedText.count))
                    typeRemaining(remaining)
                } else {
                    // Text completely changed, restart
                    displayedText = ""
                    currentIndex = 0
                    startTyping()
                }
            }
    }

    private func startTyping() {
        guard currentIndex < fullText.count else { return }

        Timer.scheduledTimer(withTimeInterval: typingSpeed, repeats: true) { timer in
            guard currentIndex < fullText.count else {
                timer.invalidate()
                return
            }

            let index = fullText.index(fullText.startIndex, offsetBy: currentIndex)
            displayedText.append(fullText[index])
            currentIndex += 1
        }
    }

    private func typeRemaining(_ text: String) {
        var charIndex = 0

        Timer.scheduledTimer(withTimeInterval: typingSpeed, repeats: true) { timer in
            guard charIndex < text.count else {
                timer.invalidate()
                return
            }

            let index = text.index(text.startIndex, offsetBy: charIndex)
            displayedText.append(text[index])
            charIndex += 1
        }
    }
}

// MARK: - Animated Text View

/// Text view that animates when content changes
struct AnimatedTextView: View {

    let text: String
    var textStyle: Font = .body
    var textColor: Color = .primary
    var animation: Animation = .easeInOut(duration: 0.2)

    var body: some View {
        Text(text)
            .font(textStyle)
            .foregroundColor(textColor)
            .fixedSize(horizontal: false, vertical: true)
            .contentTransition(.numericText())
            .animation(animation, value: text)
    }
}

// MARK: - Previews

#Preview("Streaming Text") {
    VStack(alignment: .leading, spacing: 20) {
        StreamingTextView(
            text: "This is streaming text that is being generated...",
            isStreaming: true
        )

        StreamingTextView(
            text: "This text is complete.",
            isStreaming: false
        )

        TypewriterTextView(
            fullText: "This text appears character by character."
        )
    }
    .padding()
}
