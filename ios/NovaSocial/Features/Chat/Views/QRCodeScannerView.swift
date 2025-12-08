import SwiftUI
import AVFoundation

struct QRCodeScannerView: View {
    @Binding var isPresented: Bool
    @State private var scannedCode: String?
    @State private var showAlert = false

    var body: some View {
        ZStack {
            // 相机预览
            QRScannerViewController(scannedCode: $scannedCode, isPresented: $isPresented)
                .ignoresSafeArea()

            VStack {
                // 顶部导航栏
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

                // 扫描提示
                Text("Align QR code within frame")
                    .font(Font.custom("Helvetica Neue", size: 16))
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(10)
                    .padding(.bottom, 50)
            }
        }
        .alert("QR Code Scanned", isPresented: $showAlert) {
            Button("OK") {
                isPresented = false
            }
        } message: {
            if let code = scannedCode {
                Text("Content: \(code)")
            }
        }
        .onChange(of: scannedCode) { oldValue, newValue in
            if newValue != nil {
                showAlert = true
            }
        }
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

        init(scannedCode: Binding<String?>, isPresented: Binding<Bool>) {
            _scannedCode = scannedCode
            _isPresented = isPresented
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            if let metadataObject = metadataObjects.first {
                guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else { return }
                guard let stringValue = readableObject.stringValue else { return }

                AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
                scannedCode = stringValue
            }
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

        // 添加扫描框
        let scanFrame = UIView(frame: CGRect(x: view.bounds.midX - 125, y: view.bounds.midY - 125, width: 250, height: 250))
        scanFrame.layer.borderColor = UIColor.white.cgColor
        scanFrame.layer.borderWidth = 2
        scanFrame.layer.cornerRadius = 12
        view.addSubview(scanFrame)

        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.captureSession.startRunning()
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
    }

    func failed() {
        let ac = UIAlertController(title: "Scanning not supported", message: "Your device does not support scanning QR codes. Please use a device with a camera.", preferredStyle: .alert)
        ac.addAction(UIAlertAction(title: "OK", style: .default))
        present(ac, animated: true)
        captureSession = nil
    }
}

#Preview {
    QRCodeScannerView(isPresented: .constant(true))
}
