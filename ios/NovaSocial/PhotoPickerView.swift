import SwiftUI

struct PhotoPickerView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            // 背景色
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - 顶部导航栏
                HStack(spacing: 16) {
                    // 关闭按钮
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .frame(width: 24, height: 24)

                    Spacer()

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
                .frame(height: 47)
                .padding(.horizontal, 16)
                .background(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))

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

                // MARK: - 相册网格区域
                ScrollView {
                    VStack(spacing: 2) {
                        // 第 1 行
                        HStack(spacing: 2) {
                            PhotoGridItem()
                            PhotoGridItem()
                            PhotoGridItem()
                        }

                        // 第 2 行
                        HStack(spacing: 2) {
                            PhotoGridItem()
                            PhotoGridItem()
                            PhotoGridItem()
                        }

                        // 第 3 行
                        HStack(spacing: 2) {
                            PhotoGridItem()
                            PhotoGridItem()
                            PhotoGridItem()
                        }

                        // 第 4 行
                        HStack(spacing: 2) {
                            PhotoGridItem()
                            PhotoGridItem()
                            PhotoGridItem()
                        }

                        // 第 5 行
                        HStack(spacing: 2) {
                            PhotoGridItem()
                            PhotoGridItem()
                            PhotoGridItem()
                        }

                        // 第 6 行
                        HStack(spacing: 2) {
                            PhotoGridItem()
                            PhotoGridItem()
                            PhotoGridItem()
                        }
                    }
                    .padding(0)
                }
                .safeAreaInset(edge: .bottom) {
                    Color.clear.frame(height: 20)
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
    PhotoPickerView()
}
