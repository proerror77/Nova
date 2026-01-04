import SwiftUI
import MapKit
import CoreLocation

struct LocationPickerView: View {
    @Binding var selectedLocation: String
    @Binding var isPresented: Bool

    @StateObject private var locationManager = LocationPickerManager()
    @State private var searchText = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var selectedMapItem: MKMapItem?
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var isSearching = false

    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.97, green: 0.97, blue: 0.97)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // MARK: - 搜索框
                    searchBar

                    // MARK: - 地图视图
                    mapView

                    // MARK: - 位置列表
                    locationList
                }
            }
            .navigationTitle("Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if let item = selectedMapItem {
                            selectedLocation = formatLocationName(item)
                        }
                        isPresented = false
                    }
                    .disabled(selectedMapItem == nil)
                    .foregroundColor(selectedMapItem == nil ? .gray : Color(red: 0.82, green: 0.13, blue: 0.25))
                }
            }
        }
        .onAppear {
            locationManager.requestPermission()
            // 设置初始相机位置
            if let location = locationManager.location {
                cameraPosition = .region(MKCoordinateRegion(
                    center: location.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                ))
            }
        }
        .onChange(of: locationManager.location) { _, newLocation in
            if let location = newLocation, selectedMapItem == nil {
                cameraPosition = .region(MKCoordinateRegion(
                    center: location.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                ))
            }
        }
    }

    // MARK: - 搜索栏
    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(Font.custom("SFProDisplay-Regular", size: 15.f))
                .foregroundColor(Color(red: 0.69, green: 0.68, blue: 0.68))

            TextField("Search location", text: $searchText)
                .font(Font.custom("SFProDisplay-Regular", size: 15.f))
                .foregroundColor(.black)
                .autocorrectionDisabled()
                .onChange(of: searchText) { _, newValue in
                    searchLocations(query: newValue)
                }

            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                    searchResults = []
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(Font.custom("SFProDisplay-Regular", size: 15.f))
                        .foregroundColor(Color(red: 0.69, green: 0.68, blue: 0.68))
                }
            }

            if isSearching {
                ProgressView()
                    .scaleEffect(0.8)
            }
        }
        .padding(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
        .background(Color(red: 0.93, green: 0.93, blue: 0.93))
        .cornerRadius(10)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - 地图视图
    private var mapView: some View {
        Map(position: $cameraPosition, selection: $selectedMapItem) {
            // 用户当前位置
            if let userLocation = locationManager.location {
                Annotation("My Location", coordinate: userLocation.coordinate) {
                    ZStack {
                        Circle()
                            .fill(.blue.opacity(0.3))
                            .frame(width: 32, height: 32)
                        Circle()
                            .fill(.blue)
                            .frame(width: 12, height: 12)
                    }
                }
            }

            // 搜索结果标记
            ForEach(searchResults, id: \.self) { item in
                if let location = item.placemark.location {
                    Marker(item.name ?? "Location", coordinate: location.coordinate)
                        .tint(Color(red: 0.82, green: 0.13, blue: 0.25))
                        .tag(item)
                }
            }
        }
        .frame(height: 250)
        .cornerRadius(12)
        .padding(.horizontal, 16)
        .onChange(of: selectedMapItem) { _, newItem in
            if let item = newItem, let location = item.placemark.location {
                withAnimation {
                    cameraPosition = .region(MKCoordinateRegion(
                        center: location.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    ))
                }
            }
        }
    }

    // MARK: - 位置列表
    private var locationList: some View {
        ScrollView {
            VStack(spacing: 0) {
                // 当前位置选项
                if let currentPlacemark = locationManager.currentPlacemark {
                    currentLocationRow(placemark: currentPlacemark)

                    Divider()
                        .padding(.horizontal, 16)
                }

                // 搜索结果
                if searchResults.isEmpty && !searchText.isEmpty && !isSearching {
                    Text("No results found")
                        .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                        .foregroundColor(.gray)
                        .padding(.top, 20)
                } else {
                    ForEach(Array(searchResults.enumerated()), id: \.element) { index, item in
                        locationRow(item: item)

                        if index < searchResults.count - 1 {
                            Divider()
                                .padding(.horizontal, 16)
                        }
                    }
                }
            }
            .padding(.top, 12)
        }
    }

    // MARK: - 当前位置行
    private func currentLocationRow(placemark: CLPlacemark) -> some View {
        Button(action: {
            if let location = locationManager.location {
                // 创建一个 MKMapItem 用于当前位置
                let mapItem = MKMapItem(placemark: MKPlacemark(placemark: placemark))
                mapItem.name = "Current Location"
                selectedMapItem = mapItem

                // 更新相机位置
                withAnimation {
                    cameraPosition = .region(MKCoordinateRegion(
                        center: location.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    ))
                }
            }
        }) {
            HStack(spacing: 12) {
                Image(systemName: "location.fill")
                    .font(Font.custom("SFProDisplay-Regular", size: 20.f))
                    .foregroundColor(.blue)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Current Location")
                        .font(Font.custom("SFProDisplay-Medium", size: 16.f))
                        .foregroundColor(.black)

                    Text(formatPlacemark(placemark))
                        .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }

                Spacer()

                if let selected = selectedMapItem,
                   selected.name == "Current Location" {
                    Image(systemName: "checkmark.circle.fill")
                        .font(Font.custom("SFProDisplay-Regular", size: 20.f))
                        .foregroundColor(Color(red: 0.82, green: 0.13, blue: 0.25))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - 位置行
    private func locationRow(item: MKMapItem) -> some View {
        Button(action: {
            selectedMapItem = item
            if let location = item.placemark.location {
                withAnimation {
                    cameraPosition = .region(MKCoordinateRegion(
                        center: location.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    ))
                }
            }
        }) {
            HStack(spacing: 12) {
                Image(systemName: "mappin.circle.fill")
                    .font(Font.custom("SFProDisplay-Regular", size: 20.f))
                    .foregroundColor(selectedMapItem == item ? Color(red: 0.82, green: 0.13, blue: 0.25) : .gray)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name ?? "Unknown Location")
                        .font(Font.custom("SFProDisplay-Medium", size: 16.f))
                        .foregroundColor(.black)
                        .lineLimit(1)

                    Text(formatAddress(item))
                        .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                        .foregroundColor(.gray)
                        .lineLimit(1)

                    // 显示距离
                    if let userLocation = locationManager.location,
                       let itemLocation = item.placemark.location {
                        let distance = userLocation.distance(from: itemLocation)
                        Text(formatDistance(distance))
                            .font(Font.custom("SFProDisplay-Regular", size: 12.f))
                            .foregroundColor(.gray)
                    }
                }

                Spacer()

                if selectedMapItem == item {
                    Image(systemName: "checkmark.circle.fill")
                        .font(Font.custom("SFProDisplay-Regular", size: 20.f))
                        .foregroundColor(Color(red: 0.82, green: 0.13, blue: 0.25))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - 搜索位置
    private func searchLocations(query: String) {
        guard !query.isEmpty else {
            searchResults = []
            return
        }

        isSearching = true

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query

        // 优先搜索用户附近
        if let location = locationManager.location {
            request.region = MKCoordinateRegion(
                center: location.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
            )
        }

        let search = MKLocalSearch(request: request)
        search.start { response, error in
            isSearching = false

            guard let response = response else {
                print("Search error: \(error?.localizedDescription ?? "Unknown error")")
                return
            }

            searchResults = response.mapItems
        }
    }

    // MARK: - 格式化位置名称
    private func formatLocationName(_ item: MKMapItem) -> String {
        if item.name == "Current Location" {
            if let placemark = locationManager.currentPlacemark {
                return formatPlacemark(placemark)
            }
            return "Current Location"
        }

        var components: [String] = []

        if let name = item.name {
            components.append(name)
        }

        if let locality = item.placemark.locality {
            if !components.contains(locality) {
                components.append(locality)
            }
        }

        return components.joined(separator: ", ")
    }

    // MARK: - 格式化地址
    private func formatAddress(_ item: MKMapItem) -> String {
        var parts: [String] = []

        if let thoroughfare = item.placemark.thoroughfare {
            parts.append(thoroughfare)
        }

        if let locality = item.placemark.locality {
            parts.append(locality)
        }

        if let country = item.placemark.country {
            parts.append(country)
        }

        return parts.joined(separator: ", ")
    }

    // MARK: - 格式化 CLPlacemark
    private func formatPlacemark(_ placemark: CLPlacemark) -> String {
        var parts: [String] = []

        if let locality = placemark.locality {
            parts.append(locality)
        }

        if let administrativeArea = placemark.administrativeArea {
            parts.append(administrativeArea)
        }

        if let country = placemark.country {
            parts.append(country)
        }

        return parts.joined(separator: ", ")
    }

    // MARK: - 格式化距离
    private func formatDistance(_ meters: Double) -> String {
        if meters < 1000 {
            return String(format: "%.0f m", meters)
        } else {
            return String(format: "%.1f km", meters / 1000)
        }
    }
}

// MARK: - Location Manager
class LocationPickerManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var location: CLLocation?
    @Published var currentPlacemark: CLPlacemark?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        authorizationStatus = manager.authorizationStatus
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        self.location = location

        // 反向地理编码 (使用 async/await API)
        Task { @MainActor [weak self] in
            do {
                let geocoder = CLGeocoder()
                let placemarks = try await geocoder.reverseGeocodeLocation(location)
                if let placemark = placemarks.first {
                    self?.currentPlacemark = placemark
                }
            } catch {
                #if DEBUG
                print("[LocationPickerManager] Reverse geocode error: \(error)")
                #endif
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus

        if manager.authorizationStatus == .authorizedWhenInUse ||
           manager.authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
    }
}

// MARK: - Previews

#Preview("LocationPicker - Default") {
    @Previewable @State var selectedLocation = ""
    @Previewable @State var isPresented = true

    LocationPickerView(
        selectedLocation: $selectedLocation,
        isPresented: $isPresented
    )
}

#Preview("LocationPicker - Dark Mode") {
    @Previewable @State var selectedLocation = ""
    @Previewable @State var isPresented = true

    LocationPickerView(
        selectedLocation: $selectedLocation,
        isPresented: $isPresented
    )
    .preferredColorScheme(.dark)
}
