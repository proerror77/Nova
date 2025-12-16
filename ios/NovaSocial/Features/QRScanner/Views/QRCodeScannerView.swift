import SwiftUI
import AVFoundation

struct QRCodeScannerView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject private var authManager: AuthenticationManager

    @State private var scannedCode: String?
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var isProcessing = false
    @State private var scannedUserId: String?

    /// Callback when a friend is successfully added
    var onFriendAdded: ((String) -> Void)?

    private let friendsService = FriendsService()

    var body: some View {
        ZStack {
            // Camera preview
            QRScannerViewController(scannedCode: $scannedCode, isPresented: $isPresented)
                .ignoresSafeArea()

            VStack {
                // Top navigation bar
                HStack {
                    Button(action: {
                        isPresented = false
                    }) {
                        Image(systemName: "xmark")
                            .frame(width: 24, height: 24)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    .padding()

                    Spacer()
                }

                Spacer()

                // Scan hint
                if isProcessing {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                        .padding()
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(10)
                        .padding(.bottom, 50)
                } else {
                    Text(String(localized: "qr_scan_hint", defaultValue: "Align QR code within frame"))
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(10)
                        .padding(.bottom, 50)
                }
            }
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK") {
                if scannedUserId != nil {
                    // Successfully added friend, close scanner
                    isPresented = false
                } else {
                    // Error occurred, allow rescan
                    scannedCode = nil
                }
            }
        } message: {
            Text(alertMessage)
        }
        .onChange(of: scannedCode) { _, newValue in
            if let code = newValue {
                processScannedCode(code)
            }
        }
    }

    private func processScannedCode(_ code: String) {
        // Try to parse as Nova user QR code
        if let userId = QRCodeGenerator.parseUserQRCode(code) {
            // Check if trying to add self
            if userId == authManager.currentUser?.id {
                showError(
                    title: String(localized: "qr_error_title", defaultValue: "Cannot Add"),
                    message: String(localized: "qr_error_self", defaultValue: "You cannot add yourself as a friend.")
                )
                return
            }

            addFriend(userId: userId)
        } else {
            // Not a valid Nova QR code
            showError(
                title: String(localized: "qr_invalid_title", defaultValue: "Invalid QR Code"),
                message: String(localized: "qr_invalid_message", defaultValue: "This QR code is not a valid Nova user code.")
            )
        }
    }

    private func addFriend(userId: String) {
        isProcessing = true

        Task {
            do {
                try await friendsService.addFriend(userId: userId)

                await MainActor.run {
                    isProcessing = false
                    scannedUserId = userId
                    alertTitle = String(localized: "qr_success_title", defaultValue: "Friend Added")
                    alertMessage = String(localized: "qr_success_message", defaultValue: "Friend request sent successfully!")
                    showAlert = true
                    onFriendAdded?(userId)
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    showError(
                        title: String(localized: "qr_error_title", defaultValue: "Error"),
                        message: error.localizedDescription
                    )
                }
            }
        }
    }

    private func showError(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        scannedUserId = nil
        showAlert = true
    }
}

// MARK: - UIViewControllerRepresentable for Camera
struct QRScannerViewController: UIViewControllerRepresentable {
    @Binding var scannedCode: String?
    @Binding var isPresented: Bool

    func makeUIViewController(context: Context) -> QRScannerController {
        let controller = QRScannerController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QRScannerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(scannedCode: $scannedCode, isPresented: $isPresented)
    }

    class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        @Binding var scannedCode: String?
        @Binding var isPresented: Bool
        private var hasScanned = false

        init(scannedCode: Binding<String?>, isPresented: Binding<Bool>) {
            _scannedCode = scannedCode
            _isPresented = isPresented
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            // Prevent multiple scans
            guard !hasScanned else { return }

            if let metadataObject = metadataObjects.first {
                guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else { return }
                guard let stringValue = readableObject.stringValue else { return }

                hasScanned = true
                AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
                scannedCode = stringValue
            }
        }

        func resetScanner() {
            hasScanned = false
        }
    }
}

// MARK: - Camera Controller
class QRScannerController: UIViewController {
    var captureSession: AVCaptureSession!
    var previewLayer: AVCaptureVideoPreviewLayer!
    weak var delegate: AVCaptureMetadataOutputObjectsDelegate?

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black
        captureSession = AVCaptureSession()

        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else { return }
        let videoInput: AVCaptureDeviceInput

        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            return
        }

        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
        } else {
            failed()
            return
        }

        let metadataOutput = AVCaptureMetadataOutput()

        if captureSession.canAddOutput(metadataOutput) {
            captureSession.addOutput(metadataOutput)

            metadataOutput.setMetadataObjectsDelegate(delegate, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr]
        } else {
            failed()
            return
        }

        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = view.layer.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)

        // Add scan frame overlay
        addScanFrameOverlay()

        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.captureSession.startRunning()
        }
    }

    private func addScanFrameOverlay() {
        let scanFrame = UIView(frame: CGRect(x: view.bounds.midX - 125, y: view.bounds.midY - 125, width: 250, height: 250))
        scanFrame.layer.borderColor = UIColor.white.cgColor
        scanFrame.layer.borderWidth = 2
        scanFrame.layer.cornerRadius = 12
        scanFrame.tag = 100
        view.addSubview(scanFrame)

        // Add corner accents
        let cornerLength: CGFloat = 30
        let cornerWidth: CGFloat = 4
        let corners: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (0, 0, cornerLength, cornerWidth), // Top-left horizontal
            (0, 0, cornerWidth, cornerLength), // Top-left vertical
            (250 - cornerLength, 0, cornerLength, cornerWidth), // Top-right horizontal
            (250 - cornerWidth, 0, cornerWidth, cornerLength), // Top-right vertical
            (0, 250 - cornerWidth, cornerLength, cornerWidth), // Bottom-left horizontal
            (0, 250 - cornerLength, cornerWidth, cornerLength), // Bottom-left vertical
            (250 - cornerLength, 250 - cornerWidth, cornerLength, cornerWidth), // Bottom-right horizontal
            (250 - cornerWidth, 250 - cornerLength, cornerWidth, cornerLength), // Bottom-right vertical
        ]

        for (x, y, width, height) in corners {
            let corner = UIView(frame: CGRect(x: x, y: y, width: width, height: height))
            corner.backgroundColor = .systemBlue
            corner.layer.cornerRadius = 2
            scanFrame.addSubview(corner)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        if captureSession.isRunning {
            DispatchQueue.global(qos: .background).async { [weak self] in
                self?.captureSession.stopRunning()
            }
        }
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        previewLayer?.frame = view.layer.bounds

        // Update scan frame position
        if let scanFrame = view.viewWithTag(100) {
            scanFrame.frame = CGRect(x: view.bounds.midX - 125, y: view.bounds.midY - 125, width: 250, height: 250)
        }
    }

    func failed() {
        let ac = UIAlertController(
            title: String(localized: "qr_camera_error_title", defaultValue: "Scanning not supported"),
            message: String(localized: "qr_camera_error_message", defaultValue: "Your device does not support scanning QR codes. Please use a device with a camera."),
            preferredStyle: .alert
        )
        ac.addAction(UIAlertAction(title: "OK", style: .default))
        present(ac, animated: true)
        captureSession = nil
    }
}

// MARK: - Previews

#Preview("QRCodeScanner - Default") {
    QRCodeScannerView(isPresented: .constant(true))
}

#Preview("QRCodeScanner - Dark Mode") {
    QRCodeScannerView(isPresented: .constant(true))
        .preferredColorScheme(.dark)
}
