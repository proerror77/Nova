import SwiftUI

// MARK: - Upload Progress Overlay

/// A floating overlay that shows upload progress across the app
struct UploadProgressOverlay: View {
    @ObservedObject var uploadManager = BackgroundUploadManager.shared
    @State private var showingFailedBanner = false

    var body: some View {
        VStack {
            Spacer()

            if let task = uploadManager.currentTask, uploadManager.isUploading {
                UploadProgressBanner(task: task, onCancel: {
                    uploadManager.cancelUpload()
                })
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let task = uploadManager.currentTask, task.status == .failed, let errorMessage = task.error {
                // Show failed banner when upload fails
                UploadFailedBanner(
                    errorMessage: errorMessage,
                    onRetry: {
                        // TODO: Implement retry - for now just dismiss
                        uploadManager.dismissCompletionBanner()
                    },
                    onDismiss: {
                        uploadManager.dismissCompletionBanner()
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if uploadManager.showCompletionBanner, let post = uploadManager.completedPost {
                UploadCompletedBanner(post: post, onDismiss: {
                    uploadManager.dismissCompletionBanner()
                })
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: uploadManager.isUploading)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: uploadManager.showCompletionBanner)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: uploadManager.currentTask?.status)
    }
}

// MARK: - Upload Progress Banner

struct UploadProgressBanner: View {
    let task: UploadTask
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Progress indicator
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.3), lineWidth: 3)
                    .frame(width: 36, height: 36)

                Circle()
                    .trim(from: 0, to: task.progress)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 36, height: 36)
                    .rotationEffect(.degrees(-90))

                if task.status == .compressing || task.status == .uploading {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                } else {
                    Text("\(Int(task.progress * 100))")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                }
            }

            // Status text
            VStack(alignment: .leading, spacing: 2) {
                Text("Posting...")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)

                Text(task.statusMessage)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.8))
            }

            Spacer()

            // Cancel button
            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.85))
                .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 100) // Above tab bar
    }
}

// MARK: - Upload Completed Banner

struct UploadCompletedBanner: View {
    let post: Post
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Success icon
            ZStack {
                Circle()
                    .fill(Color.green)
                    .frame(width: 36, height: 36)

                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
            }

            // Success text
            VStack(alignment: .leading, spacing: 2) {
                Text("Posted!")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)

                Text("Your post is now live")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.8))
            }

            Spacer()

            // Dismiss button
            Button(action: onDismiss) {
                Text("OK")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.white)
                    .cornerRadius(20)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.green.opacity(0.9))
                .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 100) // Above tab bar
    }
}

// MARK: - Upload Failed Banner

struct UploadFailedBanner: View {
    let errorMessage: String
    let onRetry: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Error icon
            ZStack {
                Circle()
                    .fill(Color.red)
                    .frame(width: 36, height: 36)

                Image(systemName: "exclamationmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
            }

            // Error text
            VStack(alignment: .leading, spacing: 2) {
                Text("Upload Failed")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)

                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(1)
            }

            Spacer()

            // Retry button
            Button(action: onRetry) {
                Text("Retry")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(16)
            }

            // Dismiss button
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.red.opacity(0.9))
                .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 100)
    }
}

// MARK: - Preview

#Preview("Upload Progress") {
    ZStack {
        Color.gray.opacity(0.3).ignoresSafeArea()

        VStack(spacing: 20) {
            UploadProgressBanner(
                task: UploadTask(
                    mediaItems: [],
                    postText: "Test post",
                    channelIds: [],
                    nameType: .realName,
                    location: nil,
                    onSuccess: nil
                ),
                onCancel: {}
            )
        }
    }
}
