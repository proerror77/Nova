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
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }

            // Modal content
            VStack {
                Spacer()

                VStack(spacing: 0) {
                    // 顶部红色指示条
                    Rectangle()
                        .fill(Color(red: 0.82, green: 0.11, blue: 0.26))
                        .frame(width: 56, height: 7)
                        .cornerRadius(3.5)
                        .padding(.top, 12)
                        .padding(.bottom, 16)

                    // 分隔线
                    Rectangle()
                        .fill(Color(red: 0.77, green: 0.77, blue: 0.77))
                        .frame(height: 0)

                    // Choose Photo
                    Button {
                        onChoosePhoto()
                        isPresented = false
                    } label: {
                        Text("Choose Photo")
                            .font(Typography.semibold18)
                            .foregroundColor(Color(red: 0.18, green: 0.18, blue: 0.18))
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color.white)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    // 分隔线
                    Rectangle()
                        .fill(Color(red: 0.77, green: 0.77, blue: 0.77))
                        .frame(height: 0.3)

                    // Take Photo
                    Button {
                        onTakePhoto()
                        isPresented = false
                    } label: {
                        Text("Take Photo")
                            .font(Typography.semibold18)
                            .foregroundColor(Color(red: 0.18, green: 0.18, blue: 0.18))
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color.white)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    // 分隔线
                    Rectangle()
                        .fill(Color(red: 0.77, green: 0.77, blue: 0.77))
                        .frame(height: 0.4)

                    // Generate Image
                    Button {
                        onGenerateImage()
                        isPresented = false
                    } label: {
                        Text("Generate Image")
                            .font(Typography.semibold18)
                            .foregroundColor(Color(red: 0.18, green: 0.18, blue: 0.18))
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color.white)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    // 分隔线
                    Rectangle()
                        .fill(Color(red: 0.77, green: 0.77, blue: 0.77))
                        .frame(height: 0.4)

                    // Write
                    Button {
                        onWrite()
                        isPresented = false
                    } label: {
                        Text("Write")
                            .font(Typography.semibold18)
                            .foregroundColor(Color(red: 0.18, green: 0.18, blue: 0.18))
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color.white)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    // 灰色分隔区
                    Rectangle()
                        .fill(Color(red: 0.93, green: 0.93, blue: 0.93))
                        .frame(height: 6)

                    // Cancel
                    Button {
                        isPresented = false
                    } label: {
                        Text("Cancel")
                            .font(Typography.semibold18)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color.white)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .background(
                    UnevenRoundedRectangle(topLeadingRadius: 11, topTrailingRadius: 11)
                        .fill(.white)
                )
                .safeAreaInset(edge: .bottom) {
                    Color.white
                        .frame(height: 0)
                }
            }
            .background(
                VStack {
                    Spacer()
                    Color.white
                        .frame(height: 50)
                }
                .ignoresSafeArea(edges: .bottom)
            )
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isPresented)
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
