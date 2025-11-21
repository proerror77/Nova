import SwiftUI
import PhotosUI

struct ProfileSettingView: View {
    @Binding var currentPage: AppPage
    @State private var firstName = "Bruce"
    @State private var lastName = "Li"
    @State private var username = "bruceli"
    @State private var dateOfBirth = "00/00/0000"
    @State private var gender = "Male"
    @State private var location = "China"
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showGenderPicker = false
    @State private var showLocationPicker = false

    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - 顶部导航栏
                HStack {
                    Button(action: {
                        currentPage = .setting
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20))
                            .foregroundColor(.black)
                    }

                    Spacer()

                    Text("Profile Setting")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(.black)

                    Spacer()

                    Button(action: {
                        // TODO: 保存个人资料
                    }) {
                        Text("Save")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(Color(red: 0.58, green: 0.58, blue: 0.58))
                    }
                }
                .frame(height: DesignTokens.topBarHeight)
                .padding(.horizontal, 20)
                .background(Color.white)

                // 分隔线
                Rectangle()
                    .fill(Color(red: 0.74, green: 0.74, blue: 0.74))
                    .frame(height: 0.5)

                ScrollView {
                    VStack(spacing: 20) {
                        // MARK: - 头像
                        ZStack {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 124, height: 124)

                            Circle()
                                .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                                .frame(width: 120, height: 120)

                            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                                Circle()
                                    .fill(Color.clear)
                                    .frame(width: 120, height: 120)
                            }
                        }
                        .padding(.top, 30)

                        // MARK: - 表单字段
                        VStack(spacing: 8) {
                            // First name & Last name
                            VStack(spacing: 0) {
                                HStack {
                                    Text("First name")
                                        .font(.system(size: 15))
                                        .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37))
                                        .frame(width: 100, alignment: .leading)

                                    TextField("", text: $firstName)
                                        .font(.system(size: 15))
                                        .foregroundColor(.black)
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)

                                Rectangle()
                                    .fill(Color(red: 0.91, green: 0.91, blue: 0.91))
                                    .frame(height: 0.5)

                                HStack {
                                    Text("Last name")
                                        .font(.system(size: 15))
                                        .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37))
                                        .frame(width: 100, alignment: .leading)

                                    TextField("", text: $lastName)
                                        .font(.system(size: 15))
                                        .foregroundColor(.black)
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                            }
                            .background(Color(red: 0.85, green: 0.85, blue: 0.85))
                            .cornerRadius(6)

                            // Username
                            HStack {
                                Text("Username")
                                    .font(.system(size: 15))
                                    .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37))
                                    .frame(width: 100, alignment: .leading)

                                TextField("", text: $username)
                                    .font(.system(size: 15))
                                    .foregroundColor(.black)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(Color(red: 0.85, green: 0.85, blue: 0.85))
                            .cornerRadius(6)

                            // Date of Birth
                            HStack {
                                Text("Date of Birth")
                                    .font(.system(size: 15))
                                    .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37))
                                    .frame(width: 100, alignment: .leading)

                                TextField("", text: $dateOfBirth)
                                    .font(.system(size: 15))
                                    .foregroundColor(.black)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(Color(red: 0.85, green: 0.85, blue: 0.85))
                            .cornerRadius(6)

                            // Gender
                            Button(action: {
                                showGenderPicker = true
                            }) {
                                HStack {
                                    Text("Gender")
                                        .font(.system(size: 15))
                                        .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37))
                                        .frame(width: 100, alignment: .leading)

                                    Text(gender)
                                        .font(.system(size: 15))
                                        .foregroundColor(.black)

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12))
                                        .foregroundColor(.gray)
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                            }
                            .background(Color(red: 0.85, green: 0.85, blue: 0.85))
                            .cornerRadius(6)

                            // Location
                            Button(action: {
                                showLocationPicker = true
                            }) {
                                HStack {
                                    Text("Location")
                                        .font(.system(size: 15))
                                        .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37))
                                        .frame(width: 100, alignment: .leading)

                                    Text(location)
                                        .font(.system(size: 15))
                                        .foregroundColor(.black)

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12))
                                        .foregroundColor(.gray)
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                            }
                            .background(Color(red: 0.85, green: 0.85, blue: 0.85))
                            .cornerRadius(6)
                        }
                        .padding(.horizontal, 12)
                    }
                }

                Spacer()
            }
        }
        .onChange(of: selectedPhotoItem) { oldValue, newValue in
            Task {
                if let photoItem = newValue,
                   let data = try? await photoItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    // TODO: 上传头像
                }
            }
        }
        .sheet(isPresented: $showGenderPicker) {
            GenderPickerView(selectedGender: $gender, isPresented: $showGenderPicker)
        }
        .sheet(isPresented: $showLocationPicker) {
            LocationPickerView(selectedLocation: $location, isPresented: $showLocationPicker)
        }
    }
}

// MARK: - Gender Picker
struct GenderPickerView: View {
    @Binding var selectedGender: String
    @Binding var isPresented: Bool

    let genders = ["Male", "Female", "Other", "Prefer not to say"]

    var body: some View {
        NavigationView {
            List(genders, id: \.self) { gender in
                Button(action: {
                    selectedGender = gender
                    isPresented = false
                }) {
                    HStack {
                        Text(gender)
                            .foregroundColor(.black)
                        Spacer()
                        if selectedGender == gender {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
            .navigationTitle("Select Gender")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
        }
    }
}

// MARK: - Location Picker
struct LocationPickerView: View {
    @Binding var selectedLocation: String
    @Binding var isPresented: Bool

    let locations = ["China", "United States", "United Kingdom", "Japan", "South Korea", "Other"]

    var body: some View {
        NavigationView {
            List(locations, id: \.self) { location in
                Button(action: {
                    selectedLocation = location
                    isPresented = false
                }) {
                    HStack {
                        Text(location)
                            .foregroundColor(.black)
                        Spacer()
                        if selectedLocation == location {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
            .navigationTitle("Select Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
        }
    }
}

#Preview {
    ProfileSettingView(currentPage: .constant(.setting))
}
