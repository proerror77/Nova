import SwiftUI
import PhotosUI

struct ProfileSettingView: View {
    @Binding var currentPage: AppPage
    @StateObject private var viewModel = ProfileSettingViewModel()

    // Photo picker
    @State private var selectedPhotoItem: PhotosPickerItem?

    // Picker sheets
    @State private var showGenderPicker = false
    @State private var showLocationPicker = false
    @State private var showDatePicker = false


    var body: some View {
        ZStack {
            DesignTokens.backgroundColor
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - Top Navigation Bar
                HStack {
                    Button(action: {
                        currentPage = .setting
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20))
                            .foregroundColor(DesignTokens.textPrimary)
                    }

                    Spacer()

                    Text(LocalizedStringKey("Profile Setting"))
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(DesignTokens.textPrimary)

                    Spacer()

                    Button(action: {
                        Task { await viewModel.saveProfile() }
                    }) {
                        if viewModel.isSaving {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Text(LocalizedStringKey("Save"))
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(viewModel.hasChanges ? DesignTokens.accentColor : DesignTokens.textMuted)
                        }
                    }
                    .disabled(viewModel.isSaving || !viewModel.hasChanges || !viewModel.isValid)
                }
                .frame(height: DesignTokens.topBarHeight)
                .padding(.horizontal, 20)
                .background(DesignTokens.surface)

                // Divider
                Rectangle()
                    .fill(DesignTokens.dividerColor)
                    .frame(height: 0.5)

                if viewModel.isLoading {
                    Spacer()
                    ProgressView(LocalizedStringKey("Loading messages..."))
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            // MARK: - Avatar
                            ZStack {
                                Circle()
                                    .fill(DesignTokens.surface)
                                    .frame(width: 124, height: 124)

                                if let image = viewModel.avatarImage {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 120, height: 120)
                                        .clipShape(Circle())
                                } else if let url = viewModel.avatarUrl, !url.isEmpty {
                                    AsyncImage(url: URL(string: url)) { phase in
                                        switch phase {
                                        case .success(let image):
                                            image
                                                .resizable()
                                                .scaledToFill()
                                        case .failure:
                                            Circle()
                                                .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                                        case .empty:
                                            ProgressView()
                                        @unknown default:
                                            Circle()
                                                .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                                        }
                                    }
                                    .frame(width: 120, height: 120)
                                    .clipShape(Circle())
                                } else {
                                    Circle()
                                        .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                                        .frame(width: 120, height: 120)
                                }

                                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                                    Circle()
                                        .fill(Color.clear)
                                        .frame(width: 120, height: 120)
                                        .overlay(
                                            Image(systemName: "camera.fill")
                                                .font(.system(size: 24))
                                                .foregroundColor(.white.opacity(0.8))
                                                .padding(8)
                                                .background(Color.black.opacity(0.5))
                                                .clipShape(Circle())
                                                .offset(x: 40, y: 40)
                                        )
                                }
                            }
                            .padding(.top, 30)

                            // MARK: - Form Fields
                            VStack(spacing: 8) {
                                // First name & Last name
                                VStack(spacing: 0) {
                                    FormRow(label: "First name", text: $viewModel.firstName)

                                    Rectangle()
                                        .fill(DesignTokens.tileSeparator)
                                        .frame(height: 0.5)

                                    FormRow(label: "Last name", text: $viewModel.lastName)
                                }
                                .background(DesignTokens.tileBackground)
                                .cornerRadius(6)

                                // Username
                                FormRow(label: "Username", text: $viewModel.username)
                                    .background(DesignTokens.tileBackground)
                                    .cornerRadius(6)

                                // Date of Birth
                                Button(action: {
                                    showDatePicker = true
                                }) {
                                    HStack {
                                        Text(LocalizedStringKey("Date of Birth"))
                                            .font(.system(size: 15))
                                            .foregroundColor(DesignTokens.textPrimary)
                                            .frame(width: 100, alignment: .leading)

                                        Text(viewModel.dateOfBirth.isEmpty ? LocalizedStringKey("Not set") : LocalizedStringKey(viewModel.formatDateForDisplay(viewModel.dateOfBirth)))
                                            .font(.system(size: 15))
                                            .foregroundColor(viewModel.dateOfBirth.isEmpty ? DesignTokens.textMuted : DesignTokens.textPrimary)

                                        Spacer()

                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12))
                                            .foregroundColor(DesignTokens.textMuted)
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                                }
                                .background(DesignTokens.tileBackground)
                                .cornerRadius(6)

                                // Gender
                                Button(action: {
                                    showGenderPicker = true
                                }) {
                                    HStack {
                                        Text(LocalizedStringKey("Gender"))
                                            .font(.system(size: 15))
                                            .foregroundColor(DesignTokens.textPrimary)
                                            .frame(width: 100, alignment: .leading)

                                        Text(viewModel.gender.displayName)
                                            .font(.system(size: 15))
                                            .foregroundColor(DesignTokens.textPrimary)

                                        Spacer()

                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12))
                                            .foregroundColor(DesignTokens.textMuted)
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                                }
                                .background(DesignTokens.tileBackground)
                                .cornerRadius(6)

                                // Location
                                Button(action: {
                                    showLocationPicker = true
                                }) {
                                    HStack {
                                        Text(LocalizedStringKey("Location"))
                                            .font(.system(size: 15))
                                            .foregroundColor(DesignTokens.textPrimary)
                                            .frame(width: 100, alignment: .leading)

                                        Text(viewModel.location.isEmpty ? LocalizedStringKey("Not set") : LocalizedStringKey(viewModel.location))
                                            .font(.system(size: 15))
                                            .foregroundColor(viewModel.location.isEmpty ? DesignTokens.textMuted : DesignTokens.textPrimary)

                                        Spacer()

                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12))
                                            .foregroundColor(.gray)
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                                }
                                .background(DesignTokens.tileBackground)
                                .cornerRadius(6)
                            }
                            .padding(.horizontal, 12)

                            // Error message (validation or save)
                            if let error = viewModel.errorMessage ?? viewModel.validationError {
                                Text(error)
                                    .font(.system(size: 14))
                                    .foregroundColor(.red)
                                    .padding(.horizontal, 12)
                            }

                            // Success message
                            if viewModel.showSuccessMessage {
                                Text(LocalizedStringKey("Profile updated successfully!"))
                                    .font(.system(size: 14))
                                    .foregroundColor(.green)
                                    .padding(.horizontal, 12)
                                    .onAppear {
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                            viewModel.showSuccessMessage = false
                                        }
                                    }
                            }
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }

                Spacer()
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
}

#Preview {
    ProfileSettingView(currentPage: .constant(.setting))
}
