import SwiftUI

// MARK: - Button Styles

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                configuration.isPressed ? Color.blue.opacity(0.8) : Color.blue
            )
            .foregroundColor(.white)
            .cornerRadius(12)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                configuration.isPressed ? Color.gray.opacity(0.2) : Color.gray.opacity(0.1)
            )
            .foregroundColor(.primary)
            .cornerRadius(12)
    }
}

// MARK: - TextField Styles

struct RoundedTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
    }
}

// MARK: - View Extensions

extension View {
    func errorAlert(isPresented: Binding<Bool>, message: String?) -> some View {
        alert("Error", isPresented: isPresented) {
            Button("OK", role: .cancel) { }
        } message: {
            if let message = message {
                Text(message)
            }
        }
    }
}
