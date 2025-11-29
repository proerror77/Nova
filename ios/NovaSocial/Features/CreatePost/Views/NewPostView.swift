import SwiftUI
import PhotosUI

struct NewPostView: View {
    @Binding var showNewPost: Bool
    @State private var postText: String = ""
    @State private var inviteAlice: Bool = false
    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var selectedImages: [UIImage] = []
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        ZStack {
            // 背景色
            Color(red: 0.97, green: 0.97, blue: 0.97)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - 顶部导航栏（与其他页面一致）
                HStack {
                    // Cancel 按钮
                    Button(action: {
                        showNewPost = false
                    }) {
                        Text("Cancel")
                            .font(Font.custom("Helvetica Neue", size: 14))
                            .lineSpacing(20)
                            .foregroundColor(.black)
                    }

                    Spacer()

                    // 标题
                    Text("Newpost")
                        .font(Font.custom("Helvetica Neue", size: 18).weight(.medium))
                        .lineSpacing(20)
                        .foregroundColor(.black)

                    Spacer()

                    // Draft 按钮
                    Button(action: {
                        // Draft action
                    }) {
                        Text("Draft")
                            .font(Font.custom("Helvetica Neue", size: 14))
                            .lineSpacing(20)
                            .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))
                    }
                }
                .frame(height: DesignTokens.topBarHeight)
                .padding(.horizontal, 16)
                .background(Color.white)

                ScrollView {
                    VStack(spacing: 0) {
                        // MARK: - Post as 部分
                        HStack(spacing: 13) {
                            Circle()
                                .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                                .frame(width: 30, height: 30)
                                .overlay(
                                    Circle()
                                        .stroke(Color(red: 0.81, green: 0.13, blue: 0.25), lineWidth: 0.50)
                                )

                            Text("Kent Peng")
                                .font(Font.custom("Helvetica Neue", size: 14).weight(.medium))
                                .lineSpacing(20)
                                .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37))

                            ZStack {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 10))
                                    .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37))
                            }
                            .frame(width: 16, height: 16)

                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 24)

                        // MARK: - 图片预览区
                        HStack(spacing: 20) {
                            if selectedImages.count > 0 {
                                ForEach(0..<min(selectedImages.count, 2), id: \.self) { index in
                                    Image(uiImage: selectedImages[index])
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 100, height: 100)
                                        .cornerRadius(10)
                                        .clipped()
                                }
                            } else {
                                // 占位图片1 - 黑色半透明 + Preview 标签
                                ZStack {
                                    Rectangle()
                                        .foregroundColor(.clear)
                                        .frame(width: 100, height: 100)
                                        .background(Color(red: 0, green: 0, blue: 0).opacity(0.20))
                                        .cornerRadius(10)

                                    VStack {
                                        Spacer()
                                        HStack {
                                            Text("Preview")
                                                .font(Font.custom("Helvetica Neue", size: 10).weight(.medium))
                                                .lineSpacing(20)
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 2)
                                                .background(Color(red: 0.82, green: 0.13, blue: 0.25))
                                                .cornerRadius(45)
                                            Spacer()
                                        }
                                        .padding(6)
                                    }
                                }

                                // 占位图片2 - 灰色 + 加号
                                ZStack {
                                    Rectangle()
                                        .foregroundColor(.clear)
                                        .frame(width: 100, height: 100)
                                        .background(Color(red: 0.91, green: 0.91, blue: 0.91))
                                        .cornerRadius(10)

                                    // X 型加号
                                    ZStack {
                                        Rectangle()
                                            .foregroundColor(.clear)
                                            .frame(width: 44, height: 0)
                                            .overlay(Rectangle().stroke(.white, lineWidth: 1.50))

                                        Rectangle()
                                            .foregroundColor(.clear)
                                            .frame(width: 44, height: 0)
                                            .overlay(Rectangle().stroke(.white, lineWidth: 1.50))
                                            .rotationEffect(.degrees(90))
                                    }
                                    .frame(width: 44, height: 44)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)

                        // MARK: - 文本输入区域
                        ZStack(alignment: .topLeading) {
                            // 占位文字
                            if postText.isEmpty {
                                Text("What do you want to talk about?")
                                    .font(Font.custom("Helvetica Neue", size: 14))
                                    .lineSpacing(20)
                                    .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37))
                                    .padding(.horizontal, 20)
                                    .padding(.top, 12)
                                    .allowsHitTesting(false)
                            }

                            TextEditor(text: $postText)
                                .font(Font.custom("Helvetica Neue", size: 14))
                                .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37))
                                .frame(height: 150)
                                .scrollContentBackground(.hidden)
                                .background(Color.clear)
                                .focused($isTextFieldFocused)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .onTapGesture {
                            isTextFieldFocused = true
                        }

                        // MARK: - Channels 和 Enhance 按钮
                        HStack(spacing: 10) {
                            // #Channels 按钮
                            HStack(spacing: 3) {
                                Text("#")
                                    .font(Font.custom("Helvetica Neue", size: 16))
                                    .lineSpacing(20)
                                    .foregroundColor(Color(red: 0.27, green: 0.27, blue: 0.27))

                                Text("Channels")
                                    .font(Font.custom("Helvetica Neue", size: 10))
                                    .lineSpacing(20)
                                    .foregroundColor(Color(red: 0.27, green: 0.27, blue: 0.27))
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 26)
                            .background(Color(red: 0.91, green: 0.91, blue: 0.91))
                            .cornerRadius(24)

                            // Enhance with alice 按钮
                            HStack(spacing: 3) {
                                Circle()
                                    .frame(width: 11, height: 11)
                                    .foregroundColor(Color(red: 0.87, green: 0.11, blue: 0.26))

                                Text("Enhance with alice")
                                    .font(Font.custom("Helvetica Neue", size: 10))
                                    .lineSpacing(20)
                                    .foregroundColor(Color(red: 0.87, green: 0.11, blue: 0.26))
                            }
                            .padding(.horizontal, 12)
                            .frame(height: 26)
                            .background(Color(red: 0.97, green: 0.92, blue: 0.92))
                            .cornerRadius(24)

                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 20)

                        Rectangle()
                            .foregroundColor(.clear)
                            .frame(height: 0)
                            .overlay(
                                Rectangle()
                                    .stroke(Color(red: 0.77, green: 0.77, blue: 0.77), lineWidth: 0.20)
                            )
                            .padding(.top, 20)

                        // MARK: - Check in 按钮
                        HStack(spacing: 6.14) {
                            Circle()
                                .stroke(Color.gray, lineWidth: 1)
                                .frame(width: 28.65, height: 28.65)

                            Text("Check in")
                                .font(Font.custom("Helvetica Neue", size: 16))
                                .lineSpacing(40.94)
                                .foregroundColor(.black)

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 20)

                        Rectangle()
                            .foregroundColor(.clear)
                            .frame(height: 0)
                            .overlay(
                                Rectangle()
                                    .stroke(Color(red: 0.77, green: 0.77, blue: 0.77), lineWidth: 0.20)
                            )

                        // MARK: - Invite alice 切换
                        HStack {
                            Circle()
                                .stroke(Color.gray, lineWidth: 1)
                                .frame(width: 20.86, height: 20.86)

                            Text("Invite alice")
                                .font(Font.custom("Helvetica Neue", size: 16))
                                .lineSpacing(40.94)
                                .foregroundColor(.black)

                            Spacer()

                            // Toggle 开关
                            Toggle("", isOn: $inviteAlice)
                                .labelsHidden()
                                .toggleStyle(SwitchToggleStyle(tint: Color(red: 0.82, green: 0.13, blue: 0.25)))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 20)

                        // MARK: - Invite Alice 提示
                        if inviteAlice {
                            HStack(spacing: 5) {
                                ZStack {
                                    Ellipse()
                                        .foregroundColor(.clear)
                                        .frame(width: 9.60, height: 9.60)
                                        .background(.white)
                                        .overlay(
                                            Ellipse()
                                                .inset(by: 0.24)
                                                .stroke(Color(red: 0.82, green: 0.13, blue: 0.25), lineWidth: 0.24)
                                        )

                                    Ellipse()
                                        .foregroundColor(.clear)
                                        .frame(width: 5.28, height: 5.28)
                                        .background(Color(red: 0.82, green: 0.13, blue: 0.25))
                                }
                                .frame(width: 9.60, height: 9.60)

                                Text("Invite Alice to join the discussion")
                                    .font(Font.custom("Helvetica Neue", size: 12).weight(.medium))
                                    .lineSpacing(20)
                                    .foregroundColor(Color(red: 0.82, green: 0.13, blue: 0.25))

                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 20)
                        }
                    }
                }

                // MARK: - Post 按钮
                Button(action: {
                    // Post action
                }) {
                    Text("Post")
                        .font(Font.custom("Helvetica Neue", size: 16).weight(.medium))
                        .lineSpacing(20)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Color(red: 0.87, green: 0.11, blue: 0.26))
                        .cornerRadius(31.50)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .background(Color(red: 0.97, green: 0.97, blue: 0.97))
            }
        }
        .sheet(isPresented: $showCamera) {
            ImagePicker(sourceType: .camera, selectedImage: .constant(nil))
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotos, maxSelectionCount: 10, matching: .images)
        .onChange(of: selectedPhotos) { oldValue, newValue in
            Task {
                selectedImages = []
                for item in newValue {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        selectedImages.append(image)
                    }
                }
            }
        }
    }
}

// MARK: - Image Picker for Camera
struct ImagePicker: UIViewControllerRepresentable {
    var sourceType: UIImagePickerController.SourceType
    @Binding var selectedImage: UIImage?
    @Environment(\.presentationMode) private var presentationMode

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.selectedImage = image
            }
            parent.presentationMode.wrappedValue.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}

#Preview {
    @Previewable @State var showNewPost = true
    NewPostView(showNewPost: $showNewPost)
}
