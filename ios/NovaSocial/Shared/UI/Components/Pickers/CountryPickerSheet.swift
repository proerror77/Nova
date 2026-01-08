import SwiftUI

// MARK: - Country Picker Sheet
/// Shared country picker component for phone number input
/// Used by CreateAccountPhoneNumberView and PhoneLoginView

struct CountryPickerSheet: View {
    @Binding var selectedCountry: CountryCodeData?
    @Binding var searchText: String
    @Binding var isPresented: Bool

    private let regionService = RegionDetectionService.shared

    var filteredCountries: [CountryCodeData] {
        regionService.searchCountries(searchText)
    }

    var priorityCountries: [CountryCodeData] {
        regionService.getPriorityCountries()
    }
    
    var recentCountries: [CountryCodeData] {
        regionService.getRecentCountries()
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Search bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                        TextField("Search country or code", text: $searchText)
                            .foregroundColor(.white)
                            .autocorrectionDisabled()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(10)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    // Country list
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            // Priority sections (when not searching)
                            if searchText.isEmpty {
                                if !recentCountries.isEmpty {
                                    Section {
                                        ForEach(recentCountries) { country in
                                            countryRow(country)
                                        }
                                    } header: {
                                        sectionHeader("Recent")
                                    }
                                }

                                Section {
                                    let filteredPriority = priorityCountries.filter { !recentCountries.contains($0) }
                                    ForEach(filteredPriority) { country in
                                        countryRow(country)
                                    }
                                } header: {
                                    sectionHeader("Popular")
                                }

                                Section {
                                    let excluded = Set(recentCountries + priorityCountries)
                                    ForEach(filteredCountries.filter { !excluded.contains($0) }) { country in
                                        countryRow(country)
                                    }
                                } header: {
                                    sectionHeader("All Countries")
                                }
                            } else {
                                ForEach(filteredCountries) { country in
                                    countryRow(country)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
            .navigationTitle("Select Country")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .foregroundColor(Color(red: 0.87, green: 0.11, blue: 0.26))
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(Font.custom("SFProDisplay-Semibold", size: 14.f))
                .foregroundColor(.gray)
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.top, 8)
    }

    private func countryRow(_ country: CountryCodeData) -> some View {
        VStack(spacing: 0) {
            Button(action: {
                selectedCountry = country
                searchText = ""
                regionService.savePreferredCountry(country)
                isPresented = false
            }) {
                HStack(spacing: 12) {
                    Text(country.flag)
                        .font(.system(size: 24))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(country.name)
                            .font(Font.custom("SFProDisplay-Regular", size: 16.f))
                            .foregroundColor(.white)
                        Text(country.localizedName)
                            .font(Font.custom("SFProDisplay-Regular", size: 12.f))
                            .foregroundColor(.gray)
                    }

                    Spacer()

                    Text(country.dialCode)
                        .font(Font.custom("SFProDisplay-Medium", size: 16.f))
                        .foregroundColor(.gray)

                    if selectedCountry?.id == country.id {
                        Image(systemName: "checkmark")
                            .foregroundColor(Color(red: 0.87, green: 0.11, blue: 0.26))
                    }
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider()
                .background(Color.white.opacity(0.1))
        }
    }
}

#Preview {
    CountryPickerSheet(
        selectedCountry: .constant(nil),
        searchText: .constant(""),
        isPresented: .constant(true)
    )
}
