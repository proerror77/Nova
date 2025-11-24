import SwiftUI
import PhotosUI

struct AliceView: View {
    @Binding var currentPage: AppPage
    @State private var showPhotoOptions = false
    @State private var showPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showGenerateImage = false

    var body: some View {
        ZStack {
            // 背景色
            DesignTokens.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - 顶部标题区域
                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        Text("alice 5.1 Fast")
                            .font(Font.custom("Helvetica Neue", size: 20))
                            .foregroundColor(DesignTokens.text)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 14))
                            .foregroundColor(DesignTokens.text)
                        Spacer()
                    }
                    .padding(.vertical, 16)
                    .background(DesignTokens.card)

                    Divider()
                        .frame(height: 1)
                        .background(DesignTokens.divider)
                }

                Spacer()

                // MARK: - 中间圆环图标
                Image("alice-center-icon")
                    .resizable()
                    .renderingMode(.original)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 140, height: 140)
                    .padding(.bottom, 40)

                Spacer()

                // MARK: - 底部区域
                VStack(spacing: 16) {
                    // 功能按钮组
                    HStack(spacing: 12) {
                        // Get Superalice 按钮
                        Button(action: {
                            // Get Superalice 操作
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "circle")
                                    .font(.system(size: 20, weight: .thin))
                                    .foregroundColor(DesignTokens.text)
                                Text("Get Superalice")
                                    .font(Font.custom("Helvetica Neue", size: 16))
                                    .foregroundColor(DesignTokens.text)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(DesignTokens.card)
                            .cornerRadius(24)
                            .overlay(
                                RoundedRectangle(cornerRadius: 24)
                                    .stroke(DesignTokens.border, lineWidth: 1)
                            )
                        }

                        // Voice Mode 按钮
                        Button(action: {
                            // Voice Mode 操作
                        }) {
                            Text("Voice Mode")
                                .font(Font.custom("Helvetica Neue", size: 16))
                                .foregroundColor(DesignTokens.text)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(DesignTokens.card)
                                .cornerRadius(24)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 24)
                                        .stroke(DesignTokens.border, lineWidth: 1)
                                )
                        }
                    }
                    .padding(.horizontal, 24)

                    // MARK: - 输入框区域
                    HStack(spacing: 12) {
                        // 加号按钮
                        Button(action: {
                            // 加号操作
                        }) {
                            Image(systemName: "plus")
                                .font(.system(size: 20))
                                .foregroundColor(DesignTokens.textLight)
                        }
                        .frame(width: 44, height: 44)

                        // 输入框
                        HStack {
                            Text("Ask any questions")
                                .font(Font.custom("Helvetica Neue", size: 16))
                                .foregroundColor(DesignTokens.placeholder)
                            Spacer()
                        }
                        .frame(height: 48)
                        .padding(.horizontal, 16)
                        .background(DesignTokens.card)
                        .cornerRadius(24)
                        .overlay(
                            RoundedRectangle(cornerRadius: 24)
                                .stroke(DesignTokens.border, lineWidth: 1)
                        )

                        // 发送按钮
                        Button(action: {
                            // 发送操作
                        }) {
                            Circle()
                                .fill(Color(red: 0.93, green: 0.35, blue: 0.42))
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Image(systemName: "paperplane.fill")
                                        .font(.system(size: 16))
                                        .foregroundColor(.white)
                                )
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                }

                // MARK: - 底部导航栏
                HStack(spacing: -20) {
                    // Home
                    VStack(spacing: 2) {
                        Image("home-icon-black")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 32, height: 22)
                        Text("Home")
                            .font(.system(size: 9))
                            .foregroundColor(DesignTokens.text)
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
                            .foregroundColor(DesignTokens.text)
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
                            .frame(width: 36, height: 36)
                        Text("")
                            .font(.system(size: 9))
                    }
                    .frame(maxWidth: .infinity)

                    // Account
                    VStack(spacing: 4) {
                        Image("Account-icon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                    }
                    .frame(maxWidth: .infinity)
                    .onTapGesture {
                        currentPage = .account
                    }
                }
                .frame(height: 60)
                .padding(.bottom, 20)
                .background(DesignTokens.card)
                .border(DesignTokens.border, width: 0.5)
                .offset(y: 35)
            }

            // MARK: - 照片选项弹窗
            if showPhotoOptions {
                photoOptionsModal
            }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotoItem, matching: .images)
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(isPresented: $showCamera)
                .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showGenerateImage) {
            GenerateImage01View(showGenerateImage: $showGenerateImage)
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
                        showPhotoPicker = true
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

#Preview {
    AliceView(currentPage: .constant(.alice))
}
