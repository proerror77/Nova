import SwiftUI

struct SaveDraftModal: View {
    @Binding var isPresented: Bool
    var onNo: () -> Void
    var onYes: () -> Void

    var body: some View {
        ZStack {
            // 背景遮罩
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    // 点击遮罩不关闭，必须选择 Yes 或 No
                }

            // 弹窗内容
            VStack(spacing: 0) {
                Text("Do you want to save it")
                    .font(Typography.semibold17)
                    .lineSpacing(20)
                    .foregroundColor(.black)
                    .padding(.top, 20)
                    .padding(.bottom, 16)

                Divider()

                HStack(spacing: 0) {
                    Button(action: {
                        withAnimation(.easeOut(duration: 0.2)) {
                            isPresented = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            onNo()
                        }
                    }) {
                        Text("No")
                            .font(Typography.semibold17)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }

                    Divider()
                        .frame(height: 44)

                    Button(action: {
                        withAnimation(.easeOut(duration: 0.2)) {
                            isPresented = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            onYes()
                        }
                    }) {
                        Text("Yes")
                            .font(Typography.semibold17)
                            .foregroundColor(Color(red: 0.87, green: 0.11, blue: 0.26))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                }
            }
            .frame(width: 270)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(red: 0.97, green: 0.97, blue: 0.97))
            )
            .scaleEffect(isPresented ? 1 : 1.1)
            .opacity(isPresented ? 1 : 0)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isPresented)
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.3)
            .ignoresSafeArea()

        SaveDraftModal(
            isPresented: .constant(true),
            onNo: {},
            onYes: {}
        )
    }
}
