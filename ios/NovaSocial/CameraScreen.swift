import SwiftUI

struct CameraScreen: View {
    @Binding var showCamera: Bool
    @State private var isVideoMode = false

    var body: some View {
        ZStack {
            // MARK: - 根据模式显示不同的屏幕
            if isVideoMode {
                VideoScreenContent(isVideoMode: $isVideoMode, showCamera: $showCamera)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else {
                CameraScreenContent(isVideoMode: $isVideoMode, showCamera: $showCamera)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isVideoMode)
    }
}

// MARK: - 拍照屏幕内容
struct CameraScreenContent: View {
    @Binding var isVideoMode: Bool
    @Binding var showCamera: Bool

    var body: some View {
        ZStack {
            // MARK: - 相机预览背景（图片）
            if let image = loadImageFromBundle() {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }

            VStack(spacing: 0) {
                // MARK: - 中间内容区域（相机预览）
                Spacer()

                // MARK: - 底部控制栏
                ZStack {
                    HStack(spacing: 0) {
                        // 左侧 - 视频按钮
                        Button(action: { isVideoMode = true }) {
                            Image(systemName: "video")
                                .font(.system(size: 22, weight: .regular))
                                .foregroundColor(.black)
                                .frame(width: 50, height: 50)
                                .background(Color.white)
                                .clipShape(Circle())
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Spacer()

                        // 占位符，保持右侧平衡
                        Color.clear
                            .frame(width: 60, height: 60)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .padding(.horizontal, 80)

                    // 中央 - 拍照按钮（蓝色大圆圈带相机图标）
                    Button(action: {}) {
                        ZStack {
                            Circle()
                                .fill(Color(red: 0.04, green: 0.40, blue: 0.76))
                                .frame(width: 80, height: 80)

                            Image(systemName: "camera")
                                .font(.system(size: 36, weight: .regular))
                                .foregroundColor(.white)
                        }
                        .frame(width: 80, height: 80)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .frame(height: 180)
                .padding(.bottom, 20)
            }

            // MARK: - 独立的 Close 按钮（顶部左侧）
            VStack {
                HStack {
                    Button(action: { showCamera = false }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .frame(width: 24, height: 24)
                    .padding(.leading, 16)
                    .padding(.top, 56)

                    Spacer()
                }

                Spacer()
            }
        }
    }

    // MARK: - 从 Assets 加载图片
    private func loadImageFromBundle() -> UIImage? {
        return UIImage(named: "camera-background")
    }
}

#Preview {
    @Previewable @State var showCamera = true
    CameraScreen(showCamera: $showCamera)
}
