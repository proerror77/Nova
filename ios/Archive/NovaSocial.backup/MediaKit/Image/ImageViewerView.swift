import SwiftUI

/// 图片浏览器 - 轻量级，支持缩放、拖动、旋转
///
/// Linus 风格：简单直接，没有花哨功能
/// - 缩放和平移
/// - 多图浏览
/// - 保存和分享
struct ImageViewerView: View {
    let images: [String]  // URL 数组
    let initialIndex: Int

    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var showControls = true

    init(images: [String], initialIndex: Int = 0) {
        self.images = images
        self.initialIndex = initialIndex
        _currentIndex = State(initialValue: initialIndex)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // 图片浏览器
            TabView(selection: $currentIndex) {
                ForEach(Array(images.enumerated()), id: \.offset) { index, url in
                    ZoomableImageView(url: url, scale: $scale, offset: $offset)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .onChange(of: currentIndex) { _ in
                resetZoom()
            }

            // 控制栏
            if showControls {
                VStack {
                    // 顶部工具栏
                    topToolbar

                    Spacer()

                    // 底部页码指示器
                    bottomToolbar
                }
            }
        }
        .statusBar(hidden: !showControls)
        .onTapGesture {
            withAnimation {
                showControls.toggle()
            }
        }
    }

    // MARK: - Top Toolbar

    private var topToolbar: some View {
        HStack {
            // 关闭按钮
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }

            Spacer()

            // 分享按钮
            Button {
                shareImage()
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }

            // 保存按钮
            Button {
                saveImage()
            } label: {
                Image(systemName: "arrow.down.circle")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }
        }
        .padding()
    }

    // MARK: - Bottom Toolbar

    private var bottomToolbar: some View {
        VStack(spacing: 8) {
            // 页码指示器
            Text("\(currentIndex + 1) / \(images.count)")
                .font(.caption)
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.5))
                .cornerRadius(12)

            // 缩略图条（可选）
            if images.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(images.enumerated()), id: \.offset) { index, url in
                            AsyncImageView(url: url)
                                .frame(width: 50, height: 50)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(currentIndex == index ? Color.white : Color.clear, lineWidth: 2)
                                )
                                .onTapGesture {
                                    withAnimation {
                                        currentIndex = index
                                    }
                                }
                        }
                    }
                    .padding(.horizontal)
                }
                .frame(height: 60)
            }
        }
        .padding(.bottom)
    }

    // MARK: - Actions

    private func resetZoom() {
        withAnimation {
            scale = 1.0
            offset = .zero
            lastScale = 1.0
            lastOffset = .zero
        }
    }

    private func shareImage() {
        guard currentIndex < images.count else { return }
        let url = images[currentIndex]

        Task {
            do {
                let image = try await ImageManager.shared.loadImage(url: url)
                await presentShareSheet(image: image)
            } catch {
                print("Failed to load image for sharing: \(error)")
            }
        }
    }

    private func saveImage() {
        guard currentIndex < images.count else { return }
        let url = images[currentIndex]

        Task {
            do {
                let image = try await ImageManager.shared.loadImage(url: url)
                await saveToPhotoLibrary(image: image)
            } catch {
                print("Failed to load image for saving: \(error)")
            }
        }
    }

    @MainActor
    private func presentShareSheet(image: UIImage) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            return
        }

        let activityVC = UIActivityViewController(
            activityItems: [image],
            applicationActivities: nil
        )

        // iPad 支持
        if let popoverController = activityVC.popoverPresentationController {
            popoverController.sourceView = rootViewController.view
            popoverController.sourceRect = CGRect(
                x: rootViewController.view.bounds.midX,
                y: rootViewController.view.bounds.midY,
                width: 0,
                height: 0
            )
            popoverController.permittedArrowDirections = []
        }

        rootViewController.present(activityVC, animated: true)
    }

    @MainActor
    private func saveToPhotoLibrary(image: UIImage) {
        ImageSaver.saveImage(image) { result in
            switch result {
            case .success:
                print("✅ Image saved to photo library")
            case .failure(let error):
                print("❌ Failed to save image: \(error)")
            }
        }
    }
}

// MARK: - Image Saver Helper

class ImageSaver: NSObject {
    private var completion: ((Result<Void, Error>) -> Void)?

    static func saveImage(_ image: UIImage, completion: @escaping (Result<Void, Error>) -> Void) {
        let saver = ImageSaver()
        saver.completion = completion
        UIImageWriteToSavedPhotosAlbum(image, saver, #selector(saver.saveCompleted(_:didFinishSavingWithError:contextInfo:)), nil)
    }

    @objc private func saveCompleted(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        if let error = error {
            completion?(.failure(error))
        } else {
            completion?(.success(()))
        }
    }
}

// MARK: - Zoomable Image View

struct ZoomableImageView: View {
    let url: String
    @Binding var scale: CGFloat
    @Binding var offset: CGSize

    @State private var lastScale: CGFloat = 1.0
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            AsyncImageView(url: url, contentMode: .fit)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .scaleEffect(scale)
                .offset(offset)
                .gesture(magnificationGesture)
                .gesture(dragGesture)
        }
    }

    // MARK: - Gestures

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let delta = value / lastScale
                lastScale = value
                scale = min(max(scale * delta, 1.0), 4.0)  // 限制缩放范围 1x-4x
            }
            .onEnded { _ in
                lastScale = 1.0
                if scale < 1.0 {
                    withAnimation {
                        scale = 1.0
                        offset = .zero
                    }
                }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }
}

// MARK: - Simple Image Viewer (单图浏览)

struct SimpleImageViewer: View {
    let imageURL: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ImageViewerView(images: [imageURL], initialIndex: 0)
    }
}

// MARK: - Preview

#Preview {
    ImageViewerView(
        images: [
            "https://picsum.photos/400/600",
            "https://picsum.photos/600/400",
            "https://picsum.photos/500/500"
        ],
        initialIndex: 0
    )
}
