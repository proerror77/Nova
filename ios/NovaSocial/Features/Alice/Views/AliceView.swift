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
    @State private var showNewPost = false
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
            if showNewPost {
                NewPostView(showNewPost: $showNewPost, initialImage: selectedImage)
                    .transition(.identity)
            } else if showGenerateImage {
                GenerateImage01View(showGenerateImage: $showGenerateImage)
                    .transition(.identity)
            } else {
                aliceContent
            }
        }
        .animation(.none, value: showNewPost)
        .animation(.none, value: showGenerateImage)
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(sourceType: .photoLibrary, selectedImage: $selectedImage)
        }
        .sheet(isPresented: $showCamera) {
            ImagePicker(sourceType: .camera, selectedImage: $selectedImage)
        }
        .onChange(of: selectedImage) { oldValue, newValue in
            // 选择/拍摄照片后，自动跳转到NewPostView
            if newValue != nil {
                showNewPost = true
            }
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
                BottomTabBar(currentPage: $currentPage, showPhotoOptions: $showPhotoOptions)
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
                PhotoOptionsModal(
                    isPresented: $showPhotoOptions,
                    onChoosePhoto: {
                        showImagePicker = true
                    },
                    onTakePhoto: {
                        showCamera = true
                    },
                    onGenerateImage: {
                        showGenerateImage = true
                    },
                    onWrite: {
                        showNewPost = true
                    }
                )
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
