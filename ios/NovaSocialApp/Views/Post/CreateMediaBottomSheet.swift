import SwiftUI
import AVFoundation

/// Instagram 风格的媒体创建底部菜单
/// 提供多个创建选项
struct CreateMediaBottomSheet: View {
    @Environment(\.dismiss) private var dismiss

    var onSelectMedia: () -> Void
    var onOpenCamera: () -> Void
    var onCreateReel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // 顶部拖动指示器
            VStack {
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(Color.gray.opacity(0.5))
                    .frame(width: 40, height: 5)
            }
            .frame(height: 16)

            VStack(spacing: 12) {
                // 标题
                Text("Create")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                Divider()
                    .padding(.horizontal)

                // 选项 1: 选择照片和视频
                CreateOptionButton(
                    icon: "photo.on.rectangle.angled",
                    iconColor: .blue,
                    title: "Select photo or video",
                    subtitle: "Choose from your library"
                ) {
                    onSelectMedia()
                    dismiss()
                }

                // 选项 2: 打开相机
                CreateOptionButton(
                    icon: "camera.fill",
                    iconColor: .green,
                    title: "Take a photo or video",
                    subtitle: "Open camera now"
                ) {
                    // 检查摄像头权限
                    checkCameraPermission()
                    onOpenCamera()
                    dismiss()
                }

                // 选项 3: 创建 Reels
                CreateOptionButton(
                    icon: "film.fill",
                    iconColor: .purple,
                    title: "Create a Reel",
                    subtitle: "Share short video"
                ) {
                    // 暂时不实现
                    dismiss()
                }

                // 选项 4: 创建故事
                CreateOptionButton(
                    icon: "circle.fill",
                    iconColor: .orange,
                    title: "Create a Story",
                    subtitle: "Share to your story"
                ) {
                    // 暂时不实现
                    dismiss()
                }

                Divider()
                    .padding(.horizontal)

                // 取消按钮
                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                        .font(.headline)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .padding(.bottom, 8)
            }
        }
        .background(Color(.systemBackground))
        .presentationDetents([.medium])
    }

    private func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break // 已授权
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                // 处理权限请求结果
            }
        case .denied, .restricted:
            // 提示用户打开权限
            break
        @unknown default:
            break
        }
    }
}

// MARK: - Option Button

struct CreateOptionButton: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(iconColor)
                    .cornerRadius(8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
                    .font(.caption2)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}

#Preview {
    CreateMediaBottomSheet(
        onSelectMedia: {},
        onOpenCamera: {},
        onCreateReel: {}
    )
}
