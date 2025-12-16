import SwiftUI
import PhotosUI

struct AliasNameView: View {
    @Binding var currentPage: AppPage

    // Form fields
    @State private var aliasName: String = "Dreamer"
    @State private var dateOfBirth: String = "16/11/2000"
    @State private var gender: String = "Enter your gender"
    @State private var profession: String = "Illustrator"
    @State private var location: String = "China"

    // Photo picker
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var avatarImage: UIImage?

    // Picker sheets
    @State private var showGenderPicker = false
    @State private var showLocationPicker = false
    @State private var showDatePicker = false

    // Card styling (matching ProfileSettingView)
    private let cardCornerRadius: CGFloat = 6
    private let cardShadowColor = Color(red: 0, green: 0, blue: 0, opacity: 0.15)
    private let cardShadowRadius: CGFloat = 5.9
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

                ScrollView {
                    VStack(spacing: 12) {
                        // MARK: - Avatar Section
                        avatarSection
                            .padding(.top, 20)
                            .padding(.bottom, 10)

                        // MARK: - Form Fields
                        VStack(spacing: 20) {
                            // Alias name
                            aliasNameCard

                            // Date of Birth
                            dateOfBirthCard

                            // Gender
                            genderCard

                            // Profession
                            professionCard

                            // Location
                            locationCard
                        }
                        .padding(.horizontal, 12)

                        // Footer text
                        Text("Alias name can be replaced again after 45 days")
                            .font(.system(size: 12))
                            .lineSpacing(20)
                            .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))
                            .padding(.top, 20)
                    }
                    .padding(.bottom, 40)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
        .onChange(of: selectedPhotoItem) { _, newValue in
            Task {
                if let photoItem = newValue,
                   let data = try? await photoItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    avatarImage = image
                }
            }
        }
        .sheet(isPresented: $showGenderPicker) {
            GenderPickerView(selectedGender: Binding(
                get: { Gender(rawValue: gender) ?? .notSet },
                set: { gender = $0.rawValue }
            ), isPresented: $showGenderPicker)
        }
        .sheet(isPresented: $showLocationPicker) {
            LocationPickerView(selectedLocation: $location, isPresented: $showLocationPicker)
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
                .font(.system(size: 18, weight: .medium))
                .lineSpacing(19)
                .foregroundColor(.black)

            Spacer()

            Button(action: {
                // TODO: Save alias profile
                currentPage = .setting
            }) {
                Text("Save")
                    .font(.system(size: 14))
                    .lineSpacing(20)
                    .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))
            }
            .frame(width: 50, alignment: .trailing)
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

                // 头像图片
                if let image = avatarImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
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
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .offset(x: 5, y: 5)
        }
    }

    // MARK: - Alias Name Card
    private var aliasNameCard: some View {
        HStack {
            Text("Alias name")
                .font(labelFont)
                .lineSpacing(19)
                .foregroundColor(labelColor)
                .frame(width: 100, alignment: .leading)

            TextField("", text: $aliasName)
                .font(valueFont)
                .foregroundColor(.black)

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(height: 42)
        .background(.white)
        .cornerRadius(cardCornerRadius)
        .shadow(color: cardShadowColor, radius: cardShadowRadius, x: 0, y: 0)
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

                Text(dateOfBirth)
                    .font(valueFont)
                    .foregroundColor(.black)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(height: 42)
        .background(.white)
        .cornerRadius(cardCornerRadius)
        .shadow(color: cardShadowColor, radius: cardShadowRadius, x: 0, y: 0)
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

                Text(gender)
                    .font(valueFont)
                    .foregroundColor(.black)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(height: 42)
        .background(.white)
        .cornerRadius(cardCornerRadius)
        .shadow(color: cardShadowColor, radius: cardShadowRadius, x: 0, y: 0)
    }

    // MARK: - Profession Card
    private var professionCard: some View {
        HStack {
            Text("Profession")
                .font(labelFont)
                .lineSpacing(19)
                .foregroundColor(labelColor)
                .frame(width: 100, alignment: .leading)

            TextField("", text: $profession)
                .font(valueFont)
                .foregroundColor(.black)

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(height: 42)
        .background(.white)
        .cornerRadius(cardCornerRadius)
        .shadow(color: cardShadowColor, radius: cardShadowRadius, x: 0, y: 0)
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

                Text(location)
                    .font(valueFont)
                    .foregroundColor(.black)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(height: 42)
        .background(.white)
        .cornerRadius(cardCornerRadius)
        .shadow(color: cardShadowColor, radius: cardShadowRadius, x: 0, y: 0)
    }
}

// MARK: - Previews

#Preview("AliasName - Default") {
    AliasNameView(currentPage: .constant(.aliasName))
        .environmentObject(AuthenticationManager.shared)
}

#Preview("AliasName - Dark Mode") {
    AliasNameView(currentPage: .constant(.aliasName))
        .environmentObject(AuthenticationManager.shared)
        .preferredColorScheme(.dark)
}
