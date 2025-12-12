import SwiftUI

struct LocationPickerView: View {
    @Binding var selectedLocation: String
    @Binding var isPresented: Bool

    @State private var searchText = ""

    // Common countries/regions list
    private let locations: [String] = [
        "United States",
        "United Kingdom",
        "Canada",
        "Australia",
        "Germany",
        "France",
        "Japan",
        "South Korea",
        "China",
        "Taiwan",
        "Hong Kong",
        "Singapore",
        "Malaysia",
        "Thailand",
        "Vietnam",
        "Philippines",
        "Indonesia",
        "India",
        "Brazil",
        "Mexico",
        "Argentina",
        "Spain",
        "Italy",
        "Netherlands",
        "Belgium",
        "Switzerland",
        "Sweden",
        "Norway",
        "Denmark",
        "Finland",
        "Poland",
        "Russia",
        "Turkey",
        "United Arab Emirates",
        "Saudi Arabia",
        "Israel",
        "South Africa",
        "Egypt",
        "New Zealand",
        "Ireland",
        "Portugal",
        "Austria",
        "Czech Republic",
        "Greece",
        "Hungary",
        "Romania",
        "Ukraine",
        "Chile",
        "Colombia",
        "Peru",
        "Venezuela"
    ].sorted()

    private var filteredLocations: [String] {
        if searchText.isEmpty {
            return locations
        }
        return locations.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15))
                        .foregroundColor(Color(red: 0.69, green: 0.68, blue: 0.68))

                    TextField("Search country or region", text: $searchText)
                        .font(.system(size: 15))
                        .foregroundColor(.black)
                        .autocorrectionDisabled()

                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15))
                                .foregroundColor(Color(red: 0.69, green: 0.68, blue: 0.68))
                        }
                    }
                }
                .padding(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                .background(Color(red: 0.93, green: 0.93, blue: 0.93))
                .cornerRadius(10)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                // Location list
                List {
                    // Clear option
                    if !selectedLocation.isEmpty {
                        Button(action: {
                            selectedLocation = ""
                            isPresented = false
                        }) {
                            HStack {
                                Text("Clear selection")
                                    .foregroundColor(.red)
                                Spacer()
                            }
                        }
                    }

                    // Country list
                    ForEach(filteredLocations, id: \.self) { location in
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
                                        .foregroundColor(Color(red: 0.82, green: 0.13, blue: 0.25))
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
            .background(Color(red: 0.97, green: 0.97, blue: 0.97))
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
    @Previewable @State var selectedLocation = ""
    @Previewable @State var isPresented = true

    LocationPickerView(
        selectedLocation: $selectedLocation,
        isPresented: $isPresented
    )
}
