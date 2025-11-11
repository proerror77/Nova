import SwiftUI

struct PhotoPickerView: View {
    @Binding var showPhotoPicker: Bool

    var body: some View {
        ZStack {
            // 背景色
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - 顶部导航栏
                HStack(spacing: 16) {
                    // 关闭按钮
                    Button(action: { showPhotoPicker = false }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .frame(width: 24, height: 24)

                    // 标题和筛选
                    HStack(spacing: 8) {
                        Text("All")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundColor(.white)

                        Image(systemName: "chevron.down")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                    }

                    Spacer()
                }
                .frame(height: DesignTokens.topBarHeight)
                .padding(.horizontal, 16)
                .background(Color.black)

                // MARK: - 标签栏（All, Video, Photos）
                HStack(spacing: 57) {
                    Text("All")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.white)

                    Text("Video")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.white)

                    Text("Photos")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.white)

                    Spacer()
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 20)

                // MARK: - 相册网格区域（仅此部分可滚动）
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 2) {
                        // 生成 18 个网格项目（6 行 × 3 列）
                        ForEach(0..<18, id: \.self) { _ in
                            PhotoGridItem()
                        }
                    }
                    .padding(0)
                    .safeAreaInset(edge: .bottom) {
                        Color.clear.frame(height: 20)
                    }
                }

                Spacer()
            }
        }
    }
}

// MARK: - 相册网格项目组件
struct PhotoGridItem: View {
    var body: some View {
        Rectangle()
            .fill(Color(red: 0.74, green: 0.74, blue: 0.74))
            .aspectRatio(1, contentMode: .fit)
    }
}

#Preview {
    @Previewable @State var showPhotoPicker = true
    PhotoPickerView(showPhotoPicker: $showPhotoPicker)
}
