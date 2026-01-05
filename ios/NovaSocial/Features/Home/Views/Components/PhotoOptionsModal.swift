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
                        Text("Upload Image")
                            .font(Font.custom("SFProDisplay-Medium", size: 18.f))
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
                            .font(Font.custom("SFProDisplay-Medium", size: 18.f))
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
                            .font(Font.custom("SFProDisplay-Medium", size: 18.f))
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
                        Text("Text Post")
                            .font(Font.custom("SFProDisplay-Medium", size: 18.f))
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
                            .font(Font.custom("SFProDisplay-Medium", size: 18.f))
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
/// Uses inline PhotosPicker style for proper multi-selection support
struct MultiPhotoPickerView: View {
    @Binding var isPresented: Bool
    var onConfirm: ([PostMediaItem]) -> Void

    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var isLoading = false
    @State private var loadingProgress: String = ""

    private let maxSelectionCount = 5

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Inline PhotosPicker - user can select multiple photos
                PhotosPicker(
                    selection: $selectedPhotos,
                    maxSelectionCount: maxSelectionCount,
                    selectionBehavior: .ordered,
                    matching: .any(of: [.images, .livePhotos, .videos]),
                    photoLibrary: .shared()
                ) {
                    Text("Select Photos")
                }
                .photosPickerStyle(.inline)
                .photosPickerDisabledCapabilities([.selectionActions])
                .frame(maxHeight: .infinity)

                // Loading indicator
                if isLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text(loadingProgress)
                            .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                            .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))
                    }
                    .padding()
                }
            }
            .navigationTitle("Choose Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add (\(selectedPhotos.count))") {
                        Task {
                            await processAndConfirm()
                        }
                    }
                    .disabled(selectedPhotos.isEmpty || isLoading)
                    .fontWeight(.semibold)
                    .foregroundColor(selectedPhotos.isEmpty ? .gray : Color(red: 0.87, green: 0.11, blue: 0.26))
                }
            }
        }
    }

    // MARK: - Process and Confirm Selection

    private func processAndConfirm() async {
        guard !selectedPhotos.isEmpty else { return }

        await MainActor.run {
            isLoading = true
            loadingProgress = "Processing \(selectedPhotos.count) photo(s)..."
        }

        do {
            let mediaItems = try await LivePhotoManager.shared.loadMedia(from: selectedPhotos, maxCount: maxSelectionCount)

            await MainActor.run {
                isLoading = false
                onConfirm(mediaItems)
                isPresented = false
            }
        } catch {
            await MainActor.run {
                isLoading = false
                loadingProgress = "Error: \(error.localizedDescription)"
            }
            #if DEBUG
            print("[MultiPhotoPickerView] Error loading media: \(error)")
            #endif
        }
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
