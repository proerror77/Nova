import SwiftUI

/// View displaying the current user's QR code for friend adding
struct MyQRCodeView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: AuthenticationManager

    @State private var qrCodeImage: Image?
    @State private var showShareSheet = false

    private var userId: String {
        authManager.currentUser?.id ?? ""
    }

    private var username: String {
        authManager.currentUser?.username ?? "User"
    }

    private var displayName: String {
        authManager.currentUser?.displayName ?? username
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                // User info
                VStack(spacing: 8) {
                    // Avatar placeholder
                    Circle()
                        .fill(Color.accentColor.opacity(0.2))
                        .frame(width: 80, height: 80)
                        .overlay {
                            Text(displayName.prefix(1).uppercased())
                                .font(.largeTitle)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.accentColor)
                        }

                    Text(displayName)
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("@\(username)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // QR Code
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.background)
                        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)

                    VStack(spacing: 16) {
                        if let qrImage = qrCodeImage {
                            qrImage
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 200, height: 200)
                        } else {
                            ProgressView()
                                .frame(width: 200, height: 200)
                        }

                        Text(String(localized: "qrcode_scan_to_add", defaultValue: "Scan to add me as a friend"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(24)
                }
                .frame(width: 280, height: 320)

                Spacer()

                // Action buttons
                HStack(spacing: 20) {
                    Button {
                        saveQRCodeToPhotos()
                    } label: {
                        Label(String(localized: "save_to_photos", defaultValue: "Save"), systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        showShareSheet = true
                    } label: {
                        Label(String(localized: "share", defaultValue: "Share"), systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 20)
            }
            .padding()
            .navigationTitle(String(localized: "my_qr_code", defaultValue: "My QR Code"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onAppear {
                generateQRCode()
            }
            .sheet(isPresented: $showShareSheet) {
                if let uiImage = QRCodeGenerator.generateUserQRCode(userId: userId, size: 512) {
                    ShareSheet(items: [uiImage])
                }
            }
        }
    }

    private func generateQRCode() {
        guard !userId.isEmpty else { return }
        qrCodeImage = QRCodeGenerator.userQRCodeImage(userId: userId, size: 400)
    }

    private func saveQRCodeToPhotos() {
        guard let uiImage = QRCodeGenerator.generateUserQRCode(userId: userId, size: 512) else {
            return
        }
        UIImageWriteToSavedPhotosAlbum(uiImage, nil, nil, nil)
    }
}

// MARK: - Share Sheet

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    MyQRCodeView()
        .environmentObject(AuthenticationManager.shared)
}
