import SwiftUI

struct ThankYouModal: View {
    @Environment(\.dismiss) var dismiss
    @Binding var showThankYouView: Bool
    @Binding var isPresented: Bool

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top Navigation Bar
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(Font.custom("SFProDisplay-Semibold", size: 24.f))
                            .foregroundColor(.black)
                    }
                    Spacer()
                    Text("Report")
                        .font(Font.custom("SFProDisplay-Semibold", size: 24.f))
                    Spacer()
                    Button(action: {}) {
                        Image(systemName: "xmark")
                            .font(Font.custom("SFProDisplay-Semibold", size: 18.f))
                            .foregroundColor(.clear)
                    }
                }
                .padding()
                .background(Color.white)

                Divider()

                // Main content
                VStack(spacing: 0) {
                    Spacer()

                    // Success checkmark icon
                    Circle()
                        .fill(Color(red: 0.8, green: 0.8, blue: 0.8))
                        .frame(width: 120, height: 120)
                        .overlay(
                            Image(systemName: "checkmark")
                                .font(Font.custom("SFProDisplay-Semibold", size: 50.f))
                                .foregroundColor(.white)
                        )
                        .padding(.bottom, 30)

                    // Thank you message
                    VStack(alignment: .center, spacing: 16) {
                        Text("Thank you for your feedback!")
                            .font(Font.custom("SFProDisplay-Bold", size: 20.f))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal)

                    Spacer()

                    // Done button
                    Button(action: {
                        isPresented = false  // 关闭 ReportModal sheet，返回 HomeView
                    }) {
                        Text("Done")
                            .font(Font.custom("SFProDisplay-Medium", size: 16.f))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, maxHeight: 46)
                            .background(Color(red: 0.81, green: 0.13, blue: 0.25))
                            .cornerRadius(23)
                    }
                    .padding(.horizontal, 40)
                    .padding(.bottom, 30)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
    }
}

// MARK: - Previews

#Preview("ThankYou - Default") {
    @Previewable @State var showThankYouView = true
    @Previewable @State var isPresented = true
    ThankYouModal(showThankYouView: $showThankYouView, isPresented: $isPresented)
}

#Preview("ThankYou - Dark Mode") {
    @Previewable @State var showThankYouView = true
    @Previewable @State var isPresented = true
    ThankYouModal(showThankYouView: $showThankYouView, isPresented: $isPresented)
        .preferredColorScheme(.dark)
}
