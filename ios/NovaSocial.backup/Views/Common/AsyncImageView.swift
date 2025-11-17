import SwiftUI

struct AsyncImageView: View {
    let url: String?
    var contentMode: ContentMode = .fill

    var body: some View {
        Group {
            if let urlString = url, let imageURL = URL(string: urlString) {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: contentMode)
                    case .failure:
                        Image(systemName: "photo")
                            .resizable()
                            .scaledToFit()
                            .foregroundColor(.gray)
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                Image(systemName: "photo")
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(.gray)
            }
        }
    }
}

/// 缓存版本异步图片视图 - 使用 ImageManager
///
/// Linus 风格：替代原生 AsyncImage，集成缓存系统
struct CachedAsyncImage: View {
    let url: String?
    var contentMode: ContentMode = .fill
    var placeholder: Image = Image(systemName: "photo")

    @StateObject private var loader = CachedImageLoader()

    var body: some View {
        Group {
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity.animation(.easeInOut(duration: 0.2)))
            } else if loader.isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
            } else {
                placeholder
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(.gray.opacity(0.3))
            }
        }
        .onAppear {
            if let url = url {
                Task {
                    await loader.loadImage(url: url)
                }
            }
        }
    }
}

// MARK: - Cached Image Loader

@MainActor
private class CachedImageLoader: ObservableObject {
    @Published var image: UIImage?
    @Published var isLoading = false

    private let imageManager = ImageManager.shared

    func loadImage(url: String) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let loadedImage = try await imageManager.loadImage(url: url)
            self.image = loadedImage
        } catch {
            print("Failed to load cached image: \(error)")
        }
    }
}

#Preview {
    VStack {
        AsyncImageView(url: "https://picsum.photos/400/400")
            .frame(width: 200, height: 200)
            .cornerRadius(12)

        CachedAsyncImage(url: "https://picsum.photos/400/400")
            .frame(width: 200, height: 200)
            .cornerRadius(12)
    }
}
