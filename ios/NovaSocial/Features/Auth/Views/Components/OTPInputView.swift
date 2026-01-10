import SwiftUI

// MARK: - OTP Input View

/// Reusable OTP code input component with visual boxes
/// Used across phone registration, phone login, and verification flows
struct OTPInputView: View {
    @Binding var code: String
    let codeLength: Int

    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            // Hidden text field for input
            TextField("", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($isFocused)
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .onChange(of: code) { _, newValue in
                    // Limit to codeLength digits
                    if newValue.count > codeLength {
                        code = String(newValue.prefix(codeLength))
                    }
                    // Only allow digits
                    code = code.filter { $0.isNumber }
                }

            // Display boxes
            HStack(spacing: 10) {
                ForEach(0..<codeLength, id: \.self) { index in
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(boxBorderColor(at: index), lineWidth: 1)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.white.opacity(0.1))
                            )
                            .frame(width: 45, height: 55)

                        Text(digit(at: index))
                            .font(Font.custom("SFProDisplay-Semibold", size: 24.f))
                            .foregroundColor(.white)
                    }
                }
            }
            .onTapGesture {
                isFocused = true
            }
        }
        .onAppear {
            isFocused = true
        }
    }

    private func digit(at index: Int) -> String {
        guard index < code.count else { return "" }
        let stringIndex = code.index(code.startIndex, offsetBy: index)
        return String(code[stringIndex])
    }

    private func boxBorderColor(at index: Int) -> Color {
        if index < code.count {
            return Color(red: 0.87, green: 0.11, blue: 0.26)
        } else if index == code.count && isFocused {
            return .white
        } else {
            return .gray.opacity(0.5)
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        OTPInputView(code: .constant("123"), codeLength: 6)
    }
}
