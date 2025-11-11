import SwiftUI

@main
struct FigmaDesignAppApp: App {
    @State private var showCameraScreen = false

    var body: some Scene {
        WindowGroup {
            ZStack {
                HomeView()

                VStack {
                    HStack {
                        Button {
                            showCameraScreen = true
                        } label: {
                            Text("📷 CameraScreen")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.black)
                                .cornerRadius(4)
                        }

                        Spacer()
                    }
                    .padding(16)

                    Spacer()
                }

                if showCameraScreen {
                    CameraScreen(showCamera: $showCameraScreen)
                        .transition(.move(edge: .bottom))
                }
            }
        }
    }
}
