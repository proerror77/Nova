import SwiftUI

// MARK: - Photo Options Modal

struct PhotoOptionsModal: View {
    @Binding var isPresented: Bool
    var onChoosePhoto: () -> Void = {}
    var onTakePhoto: () -> Void = {}
    var onGenerateImage: () -> Void = {}
    var onWrite: () -> Void = {}

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
                    Group {
                        // 背景 - 独立控制上下边距
                        DesignTokens.cardBackground
                            .frame(maxWidth: .infinity)
                            .frame(height: 356) // ← 基础高度
                            .cornerRadius(16)
                            .offset(y: 20) // ← 正数=底部增加，负数=顶部增加

                        // 顶部红色指示条
                        Rectangle()
                            .foregroundColor(.clear)
                            .frame(width: 56, height: 4)
                            .background(Color(red: 0.82, green: 0.11, blue: 0.26))
                            .cornerRadius(3.50)
                            .offset(x: 0, y: -145)

                        // Choose Photo
                        Button(action: {
                            onChoosePhoto()
                            isPresented = false
                        }) {
                            Text("Choose Photo")
                                .font(Font.custom("Helvetica Neue", size: 18).weight(.medium))
                                .foregroundColor(Color(red: 0.18, green: 0.18, blue: 0.18))
                        }
                        .offset(x: 0, y: -110)

                        // Take Photo
                        Button(action: {
                            onTakePhoto()
                            isPresented = false
                        }) {
                            Text("Take Photo")
                                .font(Font.custom("Helvetica Neue", size: 18).weight(.medium))
                                .foregroundColor(Color(red: 0.18, green: 0.18, blue: 0.18))
                        }
                        .offset(x: 0, y: -50)

                        // Generate Image
                        Button(action: {
                            onGenerateImage()
                            isPresented = false
                        }) {
                            Text("Generate Image")
                                .font(Font.custom("Helvetica Neue", size: 18).weight(.medium))
                                .foregroundColor(Color(red: 0.18, green: 0.18, blue: 0.18))
                        }
                        .offset(x: 0, y: 10)

                        // Write
                        Button(action: {
                            onWrite()
                            isPresented = false
                        }) {
                            Text("Write")
                                .font(Font.custom("Helvetica Neue", size: 18).weight(.medium))
                                .foregroundColor(.black)
                        }
                        .offset(x: 0, y: 70)

                    }

                    // 分隔线
                    Group {
                        Rectangle()
                            .fill(Color(red: 0.77, green: 0.77, blue: 0.77))
                            .frame(maxWidth: .infinity)
                            .frame(height: 0.5)
                            .offset(x: 0, y: -80)

                        Rectangle()
                            .fill(Color(red: 0.77, green: 0.77, blue: 0.77))
                            .frame(maxWidth: .infinity)
                            .frame(height: 0.5)
                            .offset(x: 0, y: -20)

                        Rectangle()
                            .fill(Color(red: 0.77, green: 0.77, blue: 0.77))
                            .frame(maxWidth: .infinity)
                            .frame(height: 0.5)
                            .offset(x: 0, y: 40)

                        // Cancel 上方分隔线
                        Rectangle()
                            .fill(Color(red: 0.93, green: 0.93, blue: 0.93))
                            .frame(maxWidth: .infinity)
                            .frame(height: 6)
                            .offset(x: 0, y: 100)

                        // Cancel
                        Button(action: {
                            isPresented = false
                        }) {
                            Text("Cancel")
                                .font(Font.custom("Helvetica Neue", size: 18).weight(.medium))
                                .foregroundColor(.black)
                        }
                        .offset(x: 0, y: 132)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 335)
                .padding(.bottom, -20)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    PhotoOptionsModal(
        isPresented: .constant(true),
        onChoosePhoto: {},
        onTakePhoto: {},
        onGenerateImage: {},
        onWrite: {}
    )
}
