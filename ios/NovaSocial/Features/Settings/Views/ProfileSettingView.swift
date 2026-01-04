import SwiftUI
import PhotosUI

struct ProfileSettingView: View {
    @Binding var currentPage: AppPage
    @State private var viewModel = ProfileSettingViewModel()

    // Photo picker
    @State private var selectedPhotoItem: PhotosPickerItem?

    // Picker sheets
    @State private var showGenderPicker = false
    @State private var showLocationPicker = false
    @State private var showDatePicker = false

    // Card styling (matching SettingsView)
    private let cardCornerRadius: CGFloat = 8
    private let cardShadowColor = Color.black.opacity(0.05)
    private let cardShadowRadius: CGFloat = 4
    private let cardShadowY: CGFloat = 2
    private let labelColor = Color(red: 0.38, green: 0.37, blue: 0.37)
    private let labelFont: Font = .system(size: 14.30, weight: .medium)
    private let valueFont: Font = .system(size: 14, weight: .medium)

    var body: some View {
        ZStack {
            Color(red: 0.97, green: 0.97, blue: 0.97)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - Top Navigation Bar
                topNavigationBar
                    .background(.white)

                if viewModel.isLoading {
                    Spacer()
                    ProgressView(LocalizedStringKey("Loading profile..."))
                    Spacer()
                } else if let error = viewModel.errorMessage {
                    // Show error state with retry
                    ErrorStateView(
                        errorMessage: error,
                        onRetry: {
                            viewModel.onAppear()
                        }
                    )
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            // MARK: - Avatar Section
                            avatarSection
                                .padding(.top, 20)
                                .padding(.bottom, 10)

                            // MARK: - Form Fields
                            VStack(spacing: 20) {
                                // First name & Last name
                                nameCard

                                // Date of Birth
                                dateOfBirthCard

                                // Gender
                                genderCard

                                // Profession
                                professionCard

                                // Identity
                                identityCard

                                // Location
                                locationCard
                            }
                            .padding(.horizontal, 12)

                            // Validation error message (inline errors, not full-screen)
                            if let error = viewModel.validationError {
                                Text(error)
                                    .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                                    .foregroundColor(.red)
                                    .padding(.horizontal, 12)
                            }

                            // Success message
                            if viewModel.showSuccessMessage {
                                Text(LocalizedStringKey("Profile updated successfully!"))
                                    .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                                    .foregroundColor(.green)
                                    .padding(.horizontal, 12)
                                    .onAppear {
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                            viewModel.showSuccessMessage = false
                                        }
                                    }
                            }
                        }
                        .padding(.bottom, 40)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
        }
        .onAppear {
            viewModel.onAppear()
        }
        .onChange(of: selectedPhotoItem) { _, newValue in
            Task {
                if let photoItem = newValue,
                   let data = try? await photoItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    viewModel.updateAvatarImage(image)
                }
            }
        }
        .sheet(isPresented: $showGenderPicker) {
            GenderPickerView(selectedGender: $viewModel.gender, isPresented: $showGenderPicker)
        }
        .sheet(isPresented: $showLocationPicker) {
            LocationPickerView(selectedLocation: $viewModel.location, isPresented: $showLocationPicker)
        }
        .sheet(isPresented: $showDatePicker) {
            DateOfBirthPickerView(dateString: $viewModel.dateOfBirth, isPresented: $showDatePicker)
        }
    }

    // MARK: - Top Navigation Bar
    private var topNavigationBar: some View {
        HStack {
            Button(action: {
                currentPage = .setting
            }) {
                Image(systemName: "chevron.left")
                    .frame(width: 24, height: 24)
                    .foregroundColor(.black)
            }
            .frame(width: 50, alignment: .leading)

            Spacer()

            Text("Profile settings")
                .font(Font.custom("SFProDisplay-Medium", size: 18.f))
                .lineSpacing(19)
                .foregroundColor(.black)

            Spacer()

            Button(action: {
                Task {
                    let success = await viewModel.saveProfile()
                    if success {
                        currentPage = .setting
                    }
                }
            }) {
                if viewModel.isSaving {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Text("Save")
                        .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                        .lineSpacing(20)
                        .foregroundColor(viewModel.canSave ? Color(red: 0.87, green: 0.11, blue: 0.26) : Color(red: 0.53, green: 0.53, blue: 0.53))
                }
            }
            .frame(width: 50, alignment: .trailing)
            .disabled(viewModel.isSaving || !viewModel.canSave)
        }
        .frame(height: 60)
        .padding(.horizontal, 20)
    }

    // MARK: - Avatar Section
    private var avatarSection: some View {
        ZStack(alignment: .bottomTrailing) {
            // 外圈白色边框
            ZStack {
                Ellipse()
                    .fill(.white)
                    .frame(width: 118, height: 118)

                // 头像图片 - 使用统一的默认头像
                if let pendingAvatar = AvatarManager.shared.pendingAvatar {
                    Image(uiImage: pendingAvatar)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 114, height: 114)
                        .clipShape(Ellipse())
                } else if let image = viewModel.avatarImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 114, height: 114)
                        .clipShape(Ellipse())
                } else if let url = viewModel.avatarUrl, !url.isEmpty {
                    AsyncImage(url: URL(string: url)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            DefaultAvatarView(size: 114)
                        case .empty:
                            ProgressView()
                        @unknown default:
                            DefaultAvatarView(size: 114)
                        }
                    }
                    .frame(width: 114, height: 114)
                    .clipShape(Ellipse())
                } else {
                    DefaultAvatarView(size: 114)
                }
            }

            // 红色加号按钮
            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.87, green: 0.11, blue: 0.26))
                        .frame(width: 32, height: 32)

                    Image(systemName: "plus")
                        .font(Font.custom("SFProDisplay-Bold", size: 14.f))
                        .foregroundColor(.white)
                }
            }
            .offset(x: 5, y: 5)
        }
    }

    // MARK: - Name Card (First name & Last name)
    private var nameCard: some View {
        VStack(spacing: 0) {
            // First name row
            HStack {
                Text("First name")
                    .font(labelFont)
                    .lineSpacing(19)
                    .foregroundColor(labelColor)
                    .frame(width: 100, alignment: .leading)

                TextField("", text: $viewModel.firstName)
                    .font(valueFont)
                    .foregroundColor(.black)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            // Separator
            Rectangle()
                .fill(Color(red: 0.90, green: 0.90, blue: 0.90))
                .frame(height: 0.5)
                .padding(.horizontal, 20)

            // Last name row
            HStack {
                Text("Last name")
                    .font(labelFont)
                    .lineSpacing(19)
                    .foregroundColor(labelColor)
                    .frame(width: 100, alignment: .leading)

                TextField("", text: $viewModel.lastName)
                    .font(valueFont)
                    .foregroundColor(.black)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .background(.white)
        .cornerRadius(cardCornerRadius)
        .shadow(color: cardShadowColor, radius: cardShadowRadius, x: 0, y: cardShadowY)
    }

    // MARK: - Date of Birth Card
    private var dateOfBirthCard: some View {
        Button(action: {
            showDatePicker = true
        }) {
            HStack {
                Text("Date of Birth")
                    .font(labelFont)
                    .lineSpacing(19)
                    .foregroundColor(labelColor)
                    .frame(width: 100, alignment: .leading)

                Text(viewModel.dateOfBirth.isEmpty ? "Not set" : viewModel.formatDateForDisplay(viewModel.dateOfBirth))
                    .font(valueFont)
                    .foregroundColor(viewModel.dateOfBirth.isEmpty ? labelColor : .black)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(.white)
        .cornerRadius(cardCornerRadius)
        .shadow(color: cardShadowColor, radius: cardShadowRadius, x: 0, y: cardShadowY)
    }

    // MARK: - Gender Card
    private var genderCard: some View {
        Button(action: {
            showGenderPicker = true
        }) {
            HStack {
                Text("Gender")
                    .font(labelFont)
                    .lineSpacing(19)
                    .foregroundColor(labelColor)
                    .frame(width: 100, alignment: .leading)

                Text(viewModel.gender.displayName)
                    .font(valueFont)
                    .foregroundColor(.black)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(Font.custom("SFProDisplay-Regular", size: 12.f))
                    .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(.white)
        .cornerRadius(cardCornerRadius)
        .shadow(color: cardShadowColor, radius: cardShadowRadius, x: 0, y: cardShadowY)
    }

    // MARK: - Profession Card
    private var professionCard: some View {
        HStack {
            Text("Profession")
                .font(labelFont)
                .lineSpacing(19)
                .foregroundColor(labelColor)
                .frame(width: 100, alignment: .leading)

            TextField("", text: $viewModel.profession)
                .font(valueFont)
                .foregroundColor(.black)

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.white)
        .cornerRadius(cardCornerRadius)
        .shadow(color: Color(red: 0, green: 0, blue: 0, opacity: 0.15), radius: 5.9, x: 0, y: 0)
    }

    // MARK: - Identity Card
    private var identityCard: some View {
        Button(action: {
            currentPage = .getVerified
        }) {
            HStack {
                Text("Identity")
                    .font(labelFont)
                    .lineSpacing(19)
                    .foregroundColor(labelColor)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(Font.custom("SFProDisplay-Regular", size: 12.f))
                    .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(.white)
        .cornerRadius(cardCornerRadius)
        .shadow(color: Color(red: 0, green: 0, blue: 0, opacity: 0.15), radius: 5.9, x: 0, y: 0)
    }

    // MARK: - Location Card
    private var locationCard: some View {
        Button(action: {
            showLocationPicker = true
        }) {
            HStack {
                Text("Location")
                    .font(labelFont)
                    .lineSpacing(19)
                    .foregroundColor(labelColor)
                    .frame(width: 100, alignment: .leading)

                Text(viewModel.location.isEmpty ? "Not set" : viewModel.location)
                    .font(valueFont)
                    .foregroundColor(viewModel.location.isEmpty ? labelColor : .black)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(Font.custom("SFProDisplay-Regular", size: 12.f))
                    .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(.white)
        .cornerRadius(cardCornerRadius)
        .shadow(color: cardShadowColor, radius: cardShadowRadius, x: 0, y: cardShadowY)
    }
}

// MARK: - Previews

#Preview("ProfileSetting - Default") {
    ProfileSettingView(currentPage: .constant(.profileSetting))
}

#Preview("ProfileSetting - Dark Mode") {
    ProfileSettingView(currentPage: .constant(.profileSetting))
        .preferredColorScheme(.dark)
}
