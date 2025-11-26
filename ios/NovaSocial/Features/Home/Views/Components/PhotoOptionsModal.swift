import SwiftUI

// MARK: - Photo Options Modal

struct PhotoOptionsModal: View {
    @Binding var isPresented: Bool
    var onChoosePhoto: () -> Void = {}
    var onTakePhoto: () -> Void = {}
    var onGenerateImage: () -> Void = {}

    var body: some View {
        ZStack {
            // Semi-transparent background overlay
            DesignTokens.overlayBackground
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }

            // Modal content
            VStack {
                Spacer()

                ZStack {
                    Rectangle()
                        .foregroundColor(.clear)
                        .frame(width: 375, height: 270)
                        .background(DesignTokens.cardBackground)
                        .cornerRadius(11)
                        .offset(x: 0, y: 0)

                    Rectangle()
                        .foregroundColor(.clear)
                        .frame(width: 56, height: 7)
                        .background(DesignTokens.accentColor)
                        .cornerRadius(3.50)
                        .offset(x: -0.50, y: -120.50)

                    // Choose Photo
                    Button(action: {
                        onChoosePhoto()
                        isPresented = false
                    }) {
                        Text("Choose Photo")
                            .font(Font.custom("Helvetica Neue", size: DesignTokens.fontTitle).weight(.medium))
                            .foregroundColor(Color(red: 0.18, green: 0.18, blue: 0.18))
                    }
                    .offset(x: 0, y: -79)

                    // Take Photo
                    Button(action: {
                        onTakePhoto()
                        isPresented = false
                    }) {
                        Text("Take Photo")
                            .font(Font.custom("Helvetica Neue", size: DesignTokens.fontTitle).weight(.medium))
                            .foregroundColor(Color(red: 0.18, green: 0.18, blue: 0.18))
                    }
                    .offset(x: 0.50, y: -21)

                    // Generate image
                    Button(action: {
                        onGenerateImage()
                        isPresented = false
                    }) {
                        Text("Generate image")
                            .font(Font.custom("Helvetica Neue", size: DesignTokens.fontTitle).weight(.medium))
                            .foregroundColor(Color(red: 0.18, green: 0.18, blue: 0.18))
                    }
                    .offset(x: 0, y: 37)

                    // Cancel
                    Button(action: {
                        isPresented = false
                    }) {
                        Text("Cancel")
                            .font(Font.custom("Helvetica Neue", size: DesignTokens.fontTitle).weight(.medium))
                            .lineSpacing(20)
                            .foregroundColor(.black)
                    }
                    .offset(x: -0.50, y: 105)

                    // Dividers
                    Rectangle()
                        .foregroundColor(.clear)
                        .frame(width: 375, height: 0)
                        .overlay(
                            Rectangle()
                                .stroke(DesignTokens.dividerColor, lineWidth: 3)
                        )
                        .offset(x: 0, y: 75)
                    Rectangle()
                        .foregroundColor(.clear)
                        .frame(width: 375, height: 0)
                        .overlay(
                            Rectangle()
                                .stroke(Color(red: 0.77, green: 0.77, blue: 0.77), lineWidth: 0.20)
                        )
                        .offset(x: 0, y: -50)
                    Rectangle()
                        .foregroundColor(.clear)
                        .frame(width: 375, height: 0)
                        .overlay(
                            Rectangle()
                                .stroke(Color(red: 0.77, green: 0.77, blue: 0.77), lineWidth: 0.20)
                        )
                        .offset(x: 0, y: 8)
                }
                .frame(width: 375, height: 270)
                .padding(.bottom, 50)
            }
        }
    }
}
