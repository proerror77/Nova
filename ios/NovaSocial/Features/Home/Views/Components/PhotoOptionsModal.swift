import SwiftUI
import PhotosUI

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
                            .font(.system(size: 18, weight: .medium))
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
                            .font(.system(size: 18, weight: .medium))
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
                            .font(.system(size: 18, weight: .medium))
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
                            .font(.system(size: 18, weight: .medium))
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
                            .font(.system(size: 18, weight: .medium))
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

// MARK: - Previews

#Preview("PhotoOptions - Default") {
    PhotoOptionsModal(
        isPresented: .constant(true),
        onChoosePhoto: {},
        onTakePhoto: {},
        onGenerateImage: {},
        onWrite: {}
    )
}

#Preview("PhotoOptions - Dark Mode") {
    PhotoOptionsModal(
        isPresented: .constant(true),
        onChoosePhoto: {},
        onTakePhoto: {},
        onGenerateImage: {},
        onWrite: {}
    )
    .preferredColorScheme(.dark)
}

// MARK: - Multi Photo Picker View

/// A view for selecting multiple photos (including Live Photos) before creating a post
struct MultiPhotoPickerView: View {
    @Binding var isPresented: Bool
    var onConfirm: ([PostMediaItem]) -> Void

    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var selectedMediaItems: [PostMediaItem] = []
    @State private var isLoading = false
    @State private var loadingProgress: String = ""

    private let maxSelectionCount = 5

    var body: some View {
        ZStack {
            // Background
            Color(red: 0.97, green: 0.97, blue: 0.97)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - Top Navigation Bar
                topNavigationBar

                if isLoading {
                    // Loading state
                    loadingView
                } else if selectedMediaItems.isEmpty {
                    // Empty state - show picker prompt
                    emptyStateView
                } else {
                    // Selected photos preview
                    selectedPhotosPreview
                }

                Spacer()

                // MARK: - Bottom Actions
                if !selectedMediaItems.isEmpty && !isLoading {
                    bottomActionBar
                }
            }
        }
        .onChange(of: selectedPhotos) { _, newValue in
            Task {
                await loadSelectedMedia(from: newValue)
            }
        }
    }

    // MARK: - Top Navigation Bar

    private var topNavigationBar: some View {
        HStack {
            // Cancel button
            Button(action: {
                isPresented = false
            }) {
                Text("Cancel")
                    .font(.system(size: 14))
                    .foregroundColor(.black)
            }

            Spacer()

            // Title
            Text("Choose Photos")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.black)

            Spacer()

            // Placeholder for symmetry
            Text("Cancel")
                .font(.system(size: 14))
                .foregroundColor(.clear)
        }
        .frame(height: 56)
        .padding(.horizontal, 16)
        .background(Color.white)
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()

            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: Color(red: 0.87, green: 0.11, blue: 0.26)))
                .scaleEffect(1.2)

            Text(loadingProgress)
                .font(.system(size: 14))
                .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))

            Spacer()
        }
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()

            // Photo picker button
            PhotosPicker(
                selection: $selectedPhotos,
                maxSelectionCount: maxSelectionCount,
                matching: .any(of: [.images, .livePhotos]),
                photoLibrary: .shared()
            ) {
                VStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(red: 0.91, green: 0.91, blue: 0.91))
                            .frame(width: 120, height: 120)

                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 40))
                            .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))
                    }

                    Text("Select Photos")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(Color(red: 0.87, green: 0.11, blue: 0.26))

                    Text("Choose up to 5 photos or Live Photos")
                        .font(.system(size: 14))
                        .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))
                }
            }

            Spacer()
        }
    }

    // MARK: - Selected Photos Preview

    private var selectedPhotosPreview: some View {
        VStack(spacing: 16) {
            // Count indicator
            HStack {
                Text("\(selectedMediaItems.count)/\(maxSelectionCount) selected")
                    .font(.system(size: 14))
                    .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))

                Spacer()

                // Add more button
                if selectedMediaItems.count < maxSelectionCount {
                    PhotosPicker(
                        selection: $selectedPhotos,
                        maxSelectionCount: maxSelectionCount,
                        matching: .any(of: [.images, .livePhotos]),
                        photoLibrary: .shared()
                    ) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 12))
                            Text("Add More")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(Color(red: 0.87, green: 0.11, blue: 0.26))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            // Photos grid
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(selectedMediaItems.enumerated()), id: \.element.id) { index, item in
                        mediaItemPreview(item: item, index: index)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Media Item Preview

    @ViewBuilder
    private func mediaItemPreview(item: PostMediaItem, index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            switch item {
            case .image(let image):
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 200, height: 250)
                    .cornerRadius(12)
                    .clipped()

            case .livePhoto(let data):
                ZStack {
                    Image(uiImage: data.stillImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 200, height: 250)
                        .cornerRadius(12)
                        .clipped()

                    // Live Photo badge
                    VStack {
                        HStack {
                            LivePhotoBadge()
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(8)
                }
                .frame(width: 200, height: 250)
            }

            // Delete button
            Button(action: {
                removeItem(at: index)
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
            }
            .padding(8)
        }
    }

    // MARK: - Bottom Action Bar

    private var bottomActionBar: some View {
        VStack(spacing: 0) {
            Divider()

            Button(action: {
                onConfirm(selectedMediaItems)
                isPresented = false
            }) {
                Text("Continue")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color(red: 0.87, green: 0.11, blue: 0.26))
                    .cornerRadius(25)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .background(Color.white)
    }

    // MARK: - Load Selected Media

    private func loadSelectedMedia(from items: [PhotosPickerItem]) async {
        guard !items.isEmpty else {
            await MainActor.run {
                selectedMediaItems = []
            }
            return
        }

        await MainActor.run {
            isLoading = true
            loadingProgress = "Loading photos..."
        }

        do {
            let mediaItems = try await LivePhotoManager.shared.loadMedia(from: items, maxCount: maxSelectionCount)

            await MainActor.run {
                selectedMediaItems = mediaItems
                isLoading = false
            }
        } catch {
            #if DEBUG
            print("[MultiPhotoPickerView] Failed to load media: \(error)")
            #endif

            await MainActor.run {
                isLoading = false
            }
        }
    }

    // MARK: - Remove Item

    private func removeItem(at index: Int) {
        guard index < selectedMediaItems.count else { return }

        // Also remove from selectedPhotos to keep in sync
        if index < selectedPhotos.count {
            selectedPhotos.remove(at: index)
        }
        selectedMediaItems.remove(at: index)
    }
}

// MARK: - Multi Photo Picker Previews

#Preview("MultiPhotoPicker - Default") {
    MultiPhotoPickerView(
        isPresented: .constant(true),
        onConfirm: { items in
            print("Selected \(items.count) items")
        }
    )
}

#Preview("MultiPhotoPicker - Dark Mode") {
    MultiPhotoPickerView(
        isPresented: .constant(true),
        onConfirm: { items in
            print("Selected \(items.count) items")
        }
    )
    .preferredColorScheme(.dark)
}
