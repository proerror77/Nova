import SwiftUI

// MARK: - Alice Model Data Structure
struct AliceModel: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let isSelected: Bool
}

struct AliceView: View {
    @Binding var currentPage: AppPage
    @State private var showPhotoOptions = false
    @State private var showModelSelector = false
    @State private var showImagePicker = false
    @State private var showCamera = false
    @State private var selectedImage: UIImage?
    @State private var showGenerateImage = false
    @State private var selectedModel = "alice 5.1 Fast"

    // MARK: - Model Data
    private let aliceModels: [AliceModel] = [
        AliceModel(name: "alice 5.1 Fast", description: "fast reply", isSelected: true),
        AliceModel(name: "alice 4 mini", description: "fast reply", isSelected: false),
        AliceModel(name: "alice 4.1", description: "fast reply", isSelected: false),
        AliceModel(name: "alice 4.1 Thinking", description: "fast reply", isSelected: false),
        AliceModel(name: "alice", description: "fast reply", isSelected: false)
    ]

    var body: some View {
        ZStack {
            // 条件渲染：根据状态切换视图
            if showGenerateImage {
                GenerateImage01View(showGenerateImage: $showGenerateImage)
                    .transition(.identity)
            } else {
                aliceContent
            }
        }
        .animation(.none, value: showGenerateImage)
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(sourceType: .photoLibrary, selectedImage: $selectedImage)
        }
        .sheet(isPresented: $showCamera) {
            ImagePicker(sourceType: .camera, selectedImage: $selectedImage)
        }
    }

    // MARK: - Alice 主内容
    private var aliceContent: some View {
        ZStack {
            // 背景色
            Color(red: 0.97, green: 0.97, blue: 0.97)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - 顶部导航栏
                HStack(spacing: 5) {
                    Text(selectedModel)
                        .font(Font.custom("Helvetica Neue", size: 20).weight(.bold))
                        .foregroundColor(.black)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.black)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color.white)
                .onTapGesture {
                    showModelSelector.toggle()
                }

                Divider()

                Spacer()

                // MARK: - 底部固定区域（按钮组 + 输入框）
                VStack(spacing: 6) {
                    // 功能按钮组
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            // Get Super alice 按钮
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 18))
                                    .foregroundColor(.black)
                                Text("Get Super alice")
                                    .font(Font.custom("Inter", size: 16).weight(.medium))
                                    .foregroundColor(.black)
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 42)
                            .background(Color.white)
                            .cornerRadius(21)
                            .overlay(
                                RoundedRectangle(cornerRadius: 21)
                                    .inset(by: 0.50)
                                    .stroke(Color(red: 0.77, green: 0.77, blue: 0.77), lineWidth: 0.50)
                            )

                            // Voice Mode 按钮
                            Text("Voice Mode")
                                .font(Font.custom("Inter", size: 16).weight(.medium))
                                .foregroundColor(.black)
                                .frame(width: 131, height: 42)
                                .background(Color.white)
                                .cornerRadius(21)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 21)
                                        .inset(by: 0.50)
                                        .stroke(Color(red: 0.77, green: 0.77, blue: 0.77), lineWidth: 0.50)
                                )
                        }
                        .padding(.horizontal, 16)
                    }
                    .frame(height: 50)

                    // 输入框区域
                    HStack(spacing: 12) {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.black)
                        Text("Ask any questions")
                            .font(Font.custom("Inter", size: 16))
                            .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .frame(height: 52)
                    .background(Color.white)
                    .cornerRadius(26)
                    .overlay(
                        RoundedRectangle(cornerRadius: 26)
                            .inset(by: 0.50)
                            .stroke(Color(red: 0.77, green: 0.77, blue: 0.77), lineWidth: 0.50)
                    )
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, -25)

                // MARK: - 底部导航栏
                HStack(spacing: -20) {
                    // Home
                    VStack(spacing: 2) {
                        Image("home-icon-black")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 32, height: 22)
                        Text("Home")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.black)
                    }
                    .frame(maxWidth: .infinity)
                    .onTapGesture {
                        currentPage = .home
                    }

                    // Message
                    VStack(spacing: 4) {
                        Image("Message-icon-black")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 22, height: 22)
                        Text("Message")
                            .font(.system(size: 9))
                            .foregroundColor(.black)
                    }
                    .frame(maxWidth: .infinity)
                    .onTapGesture {
                        currentPage = .message
                    }

                    // New Post (中间按钮)
                    NewPostButtonComponent(showNewPost: $showPhotoOptions)

                    // Alice (当前页面 - 高亮)
                    VStack(spacing: -12) {
                        Image("alice-button-on")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 44, height: 44)
                        Text("")
                            .font(.system(size: 9))
                    }
                    .frame(maxWidth: .infinity)

                    // Account
                    VStack(spacing: -12) {
                        Image("Account-button-off")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 44, height: 44)
                        Text("")
                            .font(.system(size: 9))
                    }
                    .frame(maxWidth: .infinity)
                    .onTapGesture {
                        currentPage = .account
                    }
                }
                .frame(height: 60)
                .padding(.bottom, 20)
                .background(Color.white)
                .overlay(
                    Rectangle()
                        .stroke(Color(red: 0.77, green: 0.77, blue: 0.77), lineWidth: 0.20)
                )
                .offset(y: 35)
            }

            // MARK: - 中间独立图标框架
            VStack {
                Spacer()
                    .frame(height: 280)

                Image("alice-center-icon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)

                Spacer()
            }

            // MARK: - 模型选择器弹窗
            if showModelSelector {
                modelSelectorModal
            }

            // MARK: - 照片选项弹窗
            if showPhotoOptions {
                photoOptionsModal
            }
        }
    }

    // MARK: - 模型选择器弹窗
    private var modelSelectorModal: some View {
        ZStack {
            // 背景模糊遮罩（除了底部导航栏）
            VStack(spacing: 0) {
                Color.clear
                    .background(.ultraThinMaterial)
                    .ignoresSafeArea()

                // 底部导航栏区域保持清晰
                Color.clear
                    .frame(height: 95)
            }
            .onTapGesture {
                showModelSelector = false
            }

            // 模型选择器 - 使用结构化数据
            VStack {
                Spacer()
                    .frame(height: 140)

                VStack(spacing: 0) {
                    ForEach(aliceModels) { model in
                        ModelRowView(
                            model: model,
                            isSelected: model.name == selectedModel,
                            onSelect: {
                                selectedModel = model.name
                                showModelSelector = false
                            }
                        )
                    }
                }
                .frame(width: 199)
                .background(Color.white)
                .cornerRadius(16)
                .shadow(color: Color(red: 0, green: 0, blue: 0, opacity: 0.25), radius: 4.70)

                Spacer()
            }
        }
    }

    // MARK: - 照片选项弹窗
    private var photoOptionsModal: some View {
        ZStack {
            // 半透明背景遮罩
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    showPhotoOptions = false
                }

            // 弹窗内容
            VStack {
                Spacer()

                ZStack() {
                    Rectangle()
                        .foregroundColor(.clear)
                        .frame(width: 375, height: 270)
                        .background(.white)
                        .cornerRadius(11)
                        .offset(x: 0, y: 0)
                    Rectangle()
                        .foregroundColor(.clear)
                        .frame(width: 56, height: 7)
                        .background(Color(red: 0.82, green: 0.11, blue: 0.26))
                        .cornerRadius(3.50)
                        .offset(x: -0.50, y: -120.50)

                    // Choose Photo
                    Button(action: {
                        showPhotoOptions = false
                        showImagePicker = true
                    }) {
                        Text("Choose Photo")
                            .font(Font.custom("Helvetica Neue", size: 18).weight(.medium))
                            .foregroundColor(Color(red: 0.18, green: 0.18, blue: 0.18))
                    }
                    .offset(x: 0, y: -79)

                    // Take Photo
                    Button(action: {
                        showPhotoOptions = false
                        showCamera = true
                    }) {
                        Text("Take Photo")
                            .font(Font.custom("Helvetica Neue", size: 18).weight(.medium))
                            .foregroundColor(Color(red: 0.18, green: 0.18, blue: 0.18))
                    }
                    .offset(x: 0.50, y: -21)

                    // Generate image
                    Button(action: {
                        showPhotoOptions = false
                        showGenerateImage = true
                    }) {
                        Text("Generate image")
                            .font(Font.custom("Helvetica Neue", size: 18).weight(.medium))
                            .foregroundColor(Color(red: 0.18, green: 0.18, blue: 0.18))
                    }
                    .offset(x: 0, y: 37)

                    // Cancel
                    Button(action: {
                        showPhotoOptions = false
                    }) {
                        Text("Cancel")
                            .font(Font.custom("Helvetica Neue", size: 18).weight(.medium))
                            .lineSpacing(20)
                            .foregroundColor(.black)
                    }
                    .offset(x: -0.50, y: 105)

                    // 分隔线
                    Rectangle()
                        .foregroundColor(.clear)
                        .frame(width: 375, height: 0)
                        .overlay(
                            Rectangle()
                                .stroke(Color(red: 0.93, green: 0.93, blue: 0.93), lineWidth: 3)
                        )
                        .offset(x: 0, y: 75)
                    Rectangle()
                        .foregroundColor(.clear)
                        .frame(width: 375, height: 0)
                        .overlay(
                            Rectangle()
                                .stroke(Color(red: 0.77, green: 0.77, blue: 0.77), lineWidth: 0.20)
                        )
                        .offset(x: 0, y: -50)
                    Rectangle()
                        .foregroundColor(.clear)
                        .frame(width: 375, height: 0)
                        .overlay(
                            Rectangle()
                                .stroke(Color(red: 0.77, green: 0.77, blue: 0.77), lineWidth: 0.20)
                        )
                        .offset(x: 0, y: 8)
                }
                .frame(width: 375, height: 270)
                .padding(.bottom, 50)
            }
        }
    }
}

// MARK: - Model Row Component
struct ModelRowView: View {
    let model: AliceModel
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.name)
                    .font(Font.custom("Helvetica Neue", size: 16))
                    .foregroundColor(.black)

                Text(model.description)
                    .font(Font.custom("Helvetica Neue", size: 14))
                    .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(isSelected ? Color(red: 0.91, green: 0.91, blue: 0.91) : Color.clear)
            .cornerRadius(14)
            .padding(.horizontal, 6)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    AliceView(currentPage: .constant(.alice))
}
