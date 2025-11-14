import SwiftUI
import MapKit
import CoreLocation

struct LocationView: View {
    @Binding var showLocation: Bool
    @StateObject private var locationManager = LocationManager()
    @State private var searchText = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var selectedLocation: MKMapItem?
    @State private var cameraPosition: MapCameraPosition = .automatic

    var body: some View {
        ZStack {
            // MARK: - 背景色
            Color(red: 0.97, green: 0.96, blue: 0.96)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - 顶部栏（导航）
                HStack(spacing: 16) {
                    // 返回按钮
                    Button(action: { showLocation = false }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.black)
                    }

                    Spacer()

                    Text("Location")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(.black)

                    Spacer()

                    // 发送按钮（箭头）
                    Button(action: {
                        // TODO: Save selected location
                        showLocation = false
                    }) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color(red: 0.82, green: 0.13, blue: 0.25))
                    }
                    .disabled(selectedLocation == nil)
                    .opacity(selectedLocation == nil ? 0.5 : 1.0)
                }
                .frame(height: DesignTokens.topBarHeight)
                .padding(.horizontal, 16)
                .background(.white)

                // MARK: - 顶部分割线
                Divider()
                    .frame(height: 0.5)
                    .background(Color(red: 0.74, green: 0.74, blue: 0.74))

                // MARK: - 搜索框
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15))
                        .foregroundColor(Color(red: 0.69, green: 0.68, blue: 0.68))

                    TextField("Search", text: $searchText)
                        .font(.system(size: 15))
                        .foregroundColor(.black)
                        .onChange(of: searchText) { oldValue, newValue in
                            searchLocations(query: newValue)
                        }

                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                            searchResults = []
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15))
                                .foregroundColor(Color(red: 0.69, green: 0.68, blue: 0.68))
                        }
                    }
                }
                .padding(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                .frame(height: 32)
                .background(Color(red: 0.89, green: 0.88, blue: 0.87))
                .cornerRadius(37)
                .padding(EdgeInsets(top: 12, leading: 18, bottom: 16, trailing: 18))

                // MARK: - 地图视图
                Map(position: $cameraPosition, selection: $selectedLocation) {
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
                                .tint(.red)
                                .tag(item)
                        }
                    }
                }
                .frame(height: 300)
                .cornerRadius(12)
                .padding(.horizontal, 18)

                // MARK: - 位置列表
                ScrollView {
                    VStack(spacing: 0) {
                        // 当前位置按钮
                        if locationManager.location != nil {
                            Button(action: {
                                if let location = locationManager.location {
                                    cameraPosition = .region(MKCoordinateRegion(
                                        center: location.coordinate,
                                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                                    ))
                                }
                            }) {
                                HStack(spacing: 12) {
                                    Image(systemName: "location.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(.blue)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Current Location")
                                            .font(.system(size: 20))
                                            .foregroundColor(.black)

                                        if let placemark = locationManager.currentPlacemark {
                                            Text("\(placemark.locality ?? ""), \(placemark.country ?? "")")
                                                .font(.system(size: 16))
                                                .foregroundColor(Color(red: 0.55, green: 0.55, blue: 0.55))
                                        }
                                    }

                                    Spacer()
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 12)
                            }

                            Divider()
                                .frame(height: 0.5)
                                .background(Color(red: 0.80, green: 0.80, blue: 0.80))
                        }

                        // 搜索结果列表
                        ForEach(Array(searchResults.enumerated()), id: \.element) { index, item in
                            Button(action: {
                                selectedLocation = item
                                if let location = item.placemark.location {
                                    cameraPosition = .region(MKCoordinateRegion(
                                        center: location.coordinate,
                                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                                    ))
                                }
                            }) {
                                LocationListItem(
                                    mapItem: item,
                                    userLocation: locationManager.location,
                                    isSelected: selectedLocation == item
                                )
                            }

                            if index < searchResults.count - 1 {
                                Divider()
                                    .frame(height: 0.5)
                                    .background(Color(red: 0.80, green: 0.80, blue: 0.80))
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                }

                Spacer()

                // MARK: - 底部按钮
                if let selected = selectedLocation {
                    Button(action: {
                        // TODO: Save selected location
                        showLocation = false
                    }) {
                        Text("Add Location: \(selected.name ?? "Unknown")")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                            .background(Color(red: 0.82, green: 0.13, blue: 0.25))
                            .cornerRadius(38)
                    }
                    .padding(EdgeInsets(top: 0, leading: 18, bottom: 20, trailing: 18))
                }
            }
        }
        .onAppear {
            locationManager.requestPermission()
            if let location = locationManager.location {
                cameraPosition = .region(MKCoordinateRegion(
                    center: location.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                ))
            }
        }
    }

    private func searchLocations(query: String) {
        guard !query.isEmpty else {
            searchResults = []
            return
        }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query

        // 如果有用户位置，优先搜索附近
        if let location = locationManager.location {
            request.region = MKCoordinateRegion(
                center: location.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
            )
        }

        let search = MKLocalSearch(request: request)
        search.start { response, error in
            guard let response = response else {
                print("Search error: \(error?.localizedDescription ?? "Unknown error")")
                return
            }

            searchResults = response.mapItems
        }
    }
}

struct LocationListItem: View {
    let mapItem: MKMapItem
    let userLocation: CLLocation?
    let isSelected: Bool

    var distance: String {
        guard let userLocation = userLocation,
              let itemLocation = mapItem.placemark.location else {
            return ""
        }

        let distanceInMeters = userLocation.distance(from: itemLocation)
        let distanceInKm = distanceInMeters / 1000.0

        if distanceInKm < 1 {
            return String(format: "%.0fm", distanceInMeters)
        } else {
            return String(format: "%.1fkm", distanceInKm)
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 20))
                .foregroundColor(isSelected ? Color(red: 0.82, green: 0.13, blue: 0.25) : .gray)

            VStack(alignment: .leading, spacing: 4) {
                Text(mapItem.name ?? "Unknown Location")
                    .font(.system(size: 20))
                    .foregroundColor(.black)

                if let thoroughfare = mapItem.placemark.thoroughfare,
                   let locality = mapItem.placemark.locality {
                    Text("\(thoroughfare), \(locality)")
                        .font(.system(size: 16))
                        .foregroundColor(Color(red: 0.55, green: 0.55, blue: 0.55))
                } else if let locality = mapItem.placemark.locality,
                          let country = mapItem.placemark.country {
                    Text("\(locality), \(country)")
                        .font(.system(size: 16))
                        .foregroundColor(Color(red: 0.55, green: 0.55, blue: 0.55))
                }

                if !distance.isEmpty {
                    Text(distance)
                        .font(.system(size: 14))
                        .foregroundColor(Color(red: 0.55, green: 0.55, blue: 0.55))
                }
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(Color(red: 0.82, green: 0.13, blue: 0.25))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
    }
}

// MARK: - Location Manager
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var location: CLLocation?
    @Published var currentPlacemark: CLPlacemark?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        self.location = location

        // 反向地理编码获取地址
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            if let placemark = placemarks?.first {
                self?.currentPlacemark = placemark
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
    }
}

#Preview {
    @Previewable @State var showLocation = true
    LocationView(showLocation: $showLocation)
}
