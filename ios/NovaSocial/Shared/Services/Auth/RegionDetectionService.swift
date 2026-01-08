import Foundation
import CoreLocation
import CoreTelephony

// MARK: - Country Code Data

struct CountryCodeData: Identifiable, Hashable {
    let id: String  // ISO 3166-1 alpha-2 code (e.g., "HK", "US")
    let name: String
    let localizedName: String
    let dialCode: String
    let flag: String
    let phoneFormat: String?  // Example format for display
    let minLength: Int
    let maxLength: Int

    var displayText: String {
        "\(flag) \(dialCode)"
    }

    var fullDisplayText: String {
        "\(flag) \(name) (\(dialCode))"
    }
}

// MARK: - Region Detection Service

/// Service for detecting user's region and providing country code data
/// Uses multiple detection methods:
/// 1. Device locale
/// 2. SIM card information (CTCarrier)
/// 3. IP-based geolocation (fallback)
final class RegionDetectionService {
    static let shared = RegionDetectionService()

    // MARK: - Properties
    private enum StorageKeys {
        static let preferredCountryCode = "preferred_country_code"
        static let recentCountryCodes = "recent_country_codes"
        static let cachedDetectedCountryCode = "cached_detected_country_code"
        static let cachedDetectedCountryTimestamp = "cached_detected_country_timestamp"
    }

    /// Default country code when detection fails
    private let defaultCountryCode = "HK"

    /// Cached detected country code
    private var cachedCountryCode: String?
    private var cachedCountryTimestamp: TimeInterval?
    private let cachedCountryTTL: TimeInterval = 60 * 60 * 24 * 7
    private let maxRecentCountries = 5
    private let userDefaults = UserDefaults.standard

    /// All supported country codes
    let allCountryCodes: [CountryCodeData] = [
        // Priority countries (most common)
        CountryCodeData(id: "HK", name: "Hong Kong", localizedName: "香港", dialCode: "+852", flag: "🇭🇰", phoneFormat: "XXXX XXXX", minLength: 8, maxLength: 8),
        CountryCodeData(id: "TW", name: "Taiwan", localizedName: "台灣", dialCode: "+886", flag: "🇹🇼", phoneFormat: "9XX XXX XXX", minLength: 9, maxLength: 10),
        CountryCodeData(id: "CN", name: "China", localizedName: "中国", dialCode: "+86", flag: "🇨🇳", phoneFormat: "1XX XXXX XXXX", minLength: 11, maxLength: 11),
        CountryCodeData(id: "US", name: "United States", localizedName: "美国", dialCode: "+1", flag: "🇺🇸", phoneFormat: "(XXX) XXX-XXXX", minLength: 10, maxLength: 10),
        CountryCodeData(id: "CA", name: "Canada", localizedName: "加拿大", dialCode: "+1", flag: "🇨🇦", phoneFormat: "(XXX) XXX-XXXX", minLength: 10, maxLength: 10),
        CountryCodeData(id: "JP", name: "Japan", localizedName: "日本", dialCode: "+81", flag: "🇯🇵", phoneFormat: "XX-XXXX-XXXX", minLength: 10, maxLength: 11),
        CountryCodeData(id: "KR", name: "South Korea", localizedName: "韩国", dialCode: "+82", flag: "🇰🇷", phoneFormat: "1X-XXXX-XXXX", minLength: 9, maxLength: 11),
        CountryCodeData(id: "SG", name: "Singapore", localizedName: "新加坡", dialCode: "+65", flag: "🇸🇬", phoneFormat: "XXXX XXXX", minLength: 8, maxLength: 8),
        CountryCodeData(id: "MY", name: "Malaysia", localizedName: "马来西亚", dialCode: "+60", flag: "🇲🇾", phoneFormat: "1X-XXX XXXX", minLength: 9, maxLength: 10),
        CountryCodeData(id: "TH", name: "Thailand", localizedName: "泰国", dialCode: "+66", flag: "🇹🇭", phoneFormat: "XX XXX XXXX", minLength: 9, maxLength: 9),
        CountryCodeData(id: "VN", name: "Vietnam", localizedName: "越南", dialCode: "+84", flag: "🇻🇳", phoneFormat: "XX XXX XXXX", minLength: 9, maxLength: 10),
        CountryCodeData(id: "PH", name: "Philippines", localizedName: "菲律宾", dialCode: "+63", flag: "🇵🇭", phoneFormat: "XXX XXX XXXX", minLength: 10, maxLength: 10),
        CountryCodeData(id: "ID", name: "Indonesia", localizedName: "印度尼西亚", dialCode: "+62", flag: "🇮🇩", phoneFormat: "XXX-XXXX-XXXX", minLength: 10, maxLength: 12),
        CountryCodeData(id: "IN", name: "India", localizedName: "印度", dialCode: "+91", flag: "🇮🇳", phoneFormat: "XXXXX XXXXX", minLength: 10, maxLength: 10),

        // Europe
        CountryCodeData(id: "GB", name: "United Kingdom", localizedName: "英国", dialCode: "+44", flag: "🇬🇧", phoneFormat: "XXXX XXXXXX", minLength: 10, maxLength: 11),
        CountryCodeData(id: "DE", name: "Germany", localizedName: "德国", dialCode: "+49", flag: "🇩🇪", phoneFormat: "XXX XXXXXXXX", minLength: 10, maxLength: 11),
        CountryCodeData(id: "FR", name: "France", localizedName: "法国", dialCode: "+33", flag: "🇫🇷", phoneFormat: "X XX XX XX XX", minLength: 9, maxLength: 9),
        CountryCodeData(id: "IT", name: "Italy", localizedName: "意大利", dialCode: "+39", flag: "🇮🇹", phoneFormat: "XXX XXX XXXX", minLength: 9, maxLength: 10),
        CountryCodeData(id: "ES", name: "Spain", localizedName: "西班牙", dialCode: "+34", flag: "🇪🇸", phoneFormat: "XXX XX XX XX", minLength: 9, maxLength: 9),
        CountryCodeData(id: "NL", name: "Netherlands", localizedName: "荷兰", dialCode: "+31", flag: "🇳🇱", phoneFormat: "X XX XX XX XX", minLength: 9, maxLength: 9),
        CountryCodeData(id: "CH", name: "Switzerland", localizedName: "瑞士", dialCode: "+41", flag: "🇨🇭", phoneFormat: "XX XXX XX XX", minLength: 9, maxLength: 9),
        CountryCodeData(id: "AT", name: "Austria", localizedName: "奥地利", dialCode: "+43", flag: "🇦🇹", phoneFormat: "XXX XXXXXXX", minLength: 10, maxLength: 11),
        CountryCodeData(id: "BE", name: "Belgium", localizedName: "比利时", dialCode: "+32", flag: "🇧🇪", phoneFormat: "XXX XX XX XX", minLength: 9, maxLength: 9),
        CountryCodeData(id: "SE", name: "Sweden", localizedName: "瑞典", dialCode: "+46", flag: "🇸🇪", phoneFormat: "XX-XXX XX XX", minLength: 9, maxLength: 10),
        CountryCodeData(id: "NO", name: "Norway", localizedName: "挪威", dialCode: "+47", flag: "🇳🇴", phoneFormat: "XXX XX XXX", minLength: 8, maxLength: 8),
        CountryCodeData(id: "DK", name: "Denmark", localizedName: "丹麦", dialCode: "+45", flag: "🇩🇰", phoneFormat: "XX XX XX XX", minLength: 8, maxLength: 8),
        CountryCodeData(id: "FI", name: "Finland", localizedName: "芬兰", dialCode: "+358", flag: "🇫🇮", phoneFormat: "XX XXX XXXX", minLength: 9, maxLength: 10),
        CountryCodeData(id: "PT", name: "Portugal", localizedName: "葡萄牙", dialCode: "+351", flag: "🇵🇹", phoneFormat: "XXX XXX XXX", minLength: 9, maxLength: 9),
        CountryCodeData(id: "IE", name: "Ireland", localizedName: "爱尔兰", dialCode: "+353", flag: "🇮🇪", phoneFormat: "XX XXX XXXX", minLength: 9, maxLength: 9),
        CountryCodeData(id: "PL", name: "Poland", localizedName: "波兰", dialCode: "+48", flag: "🇵🇱", phoneFormat: "XXX XXX XXX", minLength: 9, maxLength: 9),
        CountryCodeData(id: "CZ", name: "Czech Republic", localizedName: "捷克", dialCode: "+420", flag: "🇨🇿", phoneFormat: "XXX XXX XXX", minLength: 9, maxLength: 9),
        CountryCodeData(id: "RU", name: "Russia", localizedName: "俄罗斯", dialCode: "+7", flag: "🇷🇺", phoneFormat: "XXX XXX-XX-XX", minLength: 10, maxLength: 10),
        CountryCodeData(id: "UA", name: "Ukraine", localizedName: "乌克兰", dialCode: "+380", flag: "🇺🇦", phoneFormat: "XX XXX XX XX", minLength: 9, maxLength: 9),
        CountryCodeData(id: "GR", name: "Greece", localizedName: "希腊", dialCode: "+30", flag: "🇬🇷", phoneFormat: "XXX XXX XXXX", minLength: 10, maxLength: 10),
        CountryCodeData(id: "TR", name: "Turkey", localizedName: "土耳其", dialCode: "+90", flag: "🇹🇷", phoneFormat: "XXX XXX XXXX", minLength: 10, maxLength: 10),

        // Oceania
        CountryCodeData(id: "AU", name: "Australia", localizedName: "澳大利亚", dialCode: "+61", flag: "🇦🇺", phoneFormat: "XXX XXX XXX", minLength: 9, maxLength: 9),
        CountryCodeData(id: "NZ", name: "New Zealand", localizedName: "新西兰", dialCode: "+64", flag: "🇳🇿", phoneFormat: "XX XXX XXXX", minLength: 9, maxLength: 10),

        // Middle East
        CountryCodeData(id: "AE", name: "UAE", localizedName: "阿联酋", dialCode: "+971", flag: "🇦🇪", phoneFormat: "XX XXX XXXX", minLength: 9, maxLength: 9),
        CountryCodeData(id: "SA", name: "Saudi Arabia", localizedName: "沙特阿拉伯", dialCode: "+966", flag: "🇸🇦", phoneFormat: "XX XXX XXXX", minLength: 9, maxLength: 9),
        CountryCodeData(id: "IL", name: "Israel", localizedName: "以色列", dialCode: "+972", flag: "🇮🇱", phoneFormat: "XX-XXX-XXXX", minLength: 9, maxLength: 9),

        // Americas
        CountryCodeData(id: "MX", name: "Mexico", localizedName: "墨西哥", dialCode: "+52", flag: "🇲🇽", phoneFormat: "XXX XXX XXXX", minLength: 10, maxLength: 10),
        CountryCodeData(id: "BR", name: "Brazil", localizedName: "巴西", dialCode: "+55", flag: "🇧🇷", phoneFormat: "XX XXXXX-XXXX", minLength: 10, maxLength: 11),
        CountryCodeData(id: "AR", name: "Argentina", localizedName: "阿根廷", dialCode: "+54", flag: "🇦🇷", phoneFormat: "XX XXXX-XXXX", minLength: 10, maxLength: 10),
        CountryCodeData(id: "CL", name: "Chile", localizedName: "智利", dialCode: "+56", flag: "🇨🇱", phoneFormat: "X XXXX XXXX", minLength: 9, maxLength: 9),
        CountryCodeData(id: "CO", name: "Colombia", localizedName: "哥伦比亚", dialCode: "+57", flag: "🇨🇴", phoneFormat: "XXX XXX XXXX", minLength: 10, maxLength: 10),

        // Africa
        CountryCodeData(id: "ZA", name: "South Africa", localizedName: "南非", dialCode: "+27", flag: "🇿🇦", phoneFormat: "XX XXX XXXX", minLength: 9, maxLength: 9),
        CountryCodeData(id: "EG", name: "Egypt", localizedName: "埃及", dialCode: "+20", flag: "🇪🇬", phoneFormat: "XX XXXX XXXX", minLength: 10, maxLength: 10),
        CountryCodeData(id: "NG", name: "Nigeria", localizedName: "尼日利亚", dialCode: "+234", flag: "🇳🇬", phoneFormat: "XXX XXX XXXX", minLength: 10, maxLength: 10),
        CountryCodeData(id: "KE", name: "Kenya", localizedName: "肯尼亚", dialCode: "+254", flag: "🇰🇪", phoneFormat: "XXX XXXXXX", minLength: 9, maxLength: 9),

        // Macau
        CountryCodeData(id: "MO", name: "Macau", localizedName: "澳门", dialCode: "+853", flag: "🇲🇴", phoneFormat: "XXXX XXXX", minLength: 8, maxLength: 8),
    ]

    /// Country codes indexed by ISO code for quick lookup
    private lazy var countryCodesByISO: [String: CountryCodeData] = {
        Dictionary(uniqueKeysWithValues: allCountryCodes.map { ($0.id, $0) })
    }()

    /// Country codes indexed by dial code for quick lookup
    private lazy var countryCodesByDialCode: [String: [CountryCodeData]] = {
        Dictionary(grouping: allCountryCodes, by: { $0.dialCode })
    }()

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Methods

    /// Detect user's country code using multiple methods
    /// Priority: User preference > Cached > SIM card > Device location > Locale > IP geolocation > Default
    func detectCountryCode() async -> CountryCodeData {
        // Check cache first
        if let preferred = loadPreferredCountryCode(), let data = countryCodesByISO[preferred] {
            cachedCountryCode = preferred
            return data
        }

        if let cached = loadCachedDetectedCountryCode(), let data = countryCodesByISO[cached] {
            return data
        }

        // Try SIM card first (most reliable for mobile)
        if let simCountry = detectFromSIMCard() {
            cacheDetectedCountry(simCountry)
            if let data = countryCodesByISO[simCountry] {
                #if DEBUG
                print("[RegionDetection] Detected from SIM: \(simCountry)")
                #endif
                return data
            }
        }

        // Try device location (if already authorized)
        if let locationCountry = await detectFromDeviceLocation() {
            cacheDetectedCountry(locationCountry)
            if let data = countryCodesByISO[locationCountry] {
                #if DEBUG
                print("[RegionDetection] Detected from location: \(locationCountry)")
                #endif
                return data
            }
        }

        // Try device locale
        if let localeCountry = detectFromLocale() {
            cacheDetectedCountry(localeCountry)
            if let data = countryCodesByISO[localeCountry] {
                #if DEBUG
                print("[RegionDetection] Detected from locale: \(localeCountry)")
                #endif
                return data
            }
        }

        // Try IP geolocation as fallback
        if let ipCountry = await detectFromIP() {
            cacheDetectedCountry(ipCountry)
            if let data = countryCodesByISO[ipCountry] {
                #if DEBUG
                print("[RegionDetection] Detected from IP: \(ipCountry)")
                #endif
                return data
            }
        }

        // Return default
        #if DEBUG
        print("[RegionDetection] Using default: \(defaultCountryCode)")
        #endif
        return countryCodesByISO[defaultCountryCode] ?? allCountryCodes[0]
    }

    /// Get country data by ISO code
    func getCountryData(for isoCode: String) -> CountryCodeData? {
        countryCodesByISO[isoCode.uppercased()]
    }

    /// Get country data by dial code
    func getCountryData(forDialCode dialCode: String) -> CountryCodeData? {
        countryCodesByDialCode[dialCode]?.first
    }

    /// Search countries by name or dial code
    func searchCountries(_ query: String) -> [CountryCodeData] {
        guard !query.isEmpty else { return allCountryCodes }

        let lowercasedQuery = query.lowercased()
        return allCountryCodes.filter { country in
            country.name.lowercased().contains(lowercasedQuery) ||
            country.localizedName.contains(lowercasedQuery) ||
            country.dialCode.contains(query) ||
            country.id.lowercased().contains(lowercasedQuery)
        }
    }

    /// Get priority countries (most commonly used)
    func getPriorityCountries() -> [CountryCodeData] {
        let priorityIDs = ["HK", "TW", "CN", "US", "JP", "KR", "SG", "GB", "AU"]
        return priorityIDs.compactMap { countryCodesByISO[$0] }
    }

    /// Get recent countries (most recently selected by the user)
    func getRecentCountries() -> [CountryCodeData] {
        let recentCodes = userDefaults.stringArray(forKey: StorageKeys.recentCountryCodes) ?? []
        return recentCodes.compactMap { countryCodesByISO[$0.uppercased()] }
    }

    /// Save user's preferred country selection
    func savePreferredCountry(_ country: CountryCodeData) {
        let isoCode = country.id.uppercased()
        userDefaults.set(isoCode, forKey: StorageKeys.preferredCountryCode)
        updateRecentCountries(with: isoCode)
        cacheDetectedCountry(isoCode)
    }

    /// Clear cached detection result
    func clearCache() {
        cachedCountryCode = nil
        cachedCountryTimestamp = nil
        clearCachedDetectedCountry()
    }

    // MARK: - Private Detection Methods

    /// Detect country from SIM card
    private func detectFromSIMCard() -> String? {
        let networkInfo = CTTelephonyNetworkInfo()

        // Try to get carrier info
        if let carriers = networkInfo.serviceSubscriberCellularProviders,
           let carrier = carriers.values.first,
           let isoCode = carrier.isoCountryCode?.uppercased(),
           !isoCode.isEmpty {
            return isoCode
        }

        return nil
    }

    /// Detect country from device locale
    private func detectFromLocale() -> String? {
        // Try region from current locale
        if let regionCode = Locale.current.region?.identifier.uppercased(),
           countryCodesByISO[regionCode] != nil {
            return regionCode
        }

        // Try language region
        if let languageCode = Locale.current.language.region?.identifier.uppercased(),
           countryCodesByISO[languageCode] != nil {
            return languageCode
        }

        return nil
    }

    /// Detect country from device location (if permission already granted)
    private func detectFromDeviceLocation() async -> String? {
        guard CLLocationManager.locationServicesEnabled() else { return nil }
        let status = CLLocationManager.authorizationStatus()
        guard status == .authorizedAlways || status == .authorizedWhenInUse else {
            return nil
        }

        let detector = LocationCountryDetector()
        return await detector.detectCountry()
    }

    /// Detect country from IP address using free geolocation API
    private func detectFromIP() async -> String? {
        // Use ipapi.co for free IP geolocation (no API key required for basic usage)
        guard let url = URL(string: "https://ipapi.co/json/") else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }

            struct IPResponse: Codable {
                let country_code: String?
                let country: String?
            }

            let decoded = try JSONDecoder().decode(IPResponse.self, from: data)
            return decoded.country_code?.uppercased()

        } catch {
            #if DEBUG
            print("[RegionDetection] IP detection failed: \(error)")
            #endif
            return nil
        }
    }

    // MARK: - Cached Detection + Preference

    private func loadPreferredCountryCode() -> String? {
        userDefaults.string(forKey: StorageKeys.preferredCountryCode)?.uppercased()
    }

    private func loadCachedDetectedCountryCode() -> String? {
        let now = Date().timeIntervalSince1970

        if let cached = cachedCountryCode,
           let timestamp = cachedCountryTimestamp,
           now - timestamp < cachedCountryTTL {
            return cached
        }

        guard let storedCode = userDefaults.string(forKey: StorageKeys.cachedDetectedCountryCode) else {
            return nil
        }

        let storedTimestamp = userDefaults.double(forKey: StorageKeys.cachedDetectedCountryTimestamp)
        guard storedTimestamp > 0, now - storedTimestamp < cachedCountryTTL else {
            clearCachedDetectedCountry()
            return nil
        }

        cachedCountryCode = storedCode
        cachedCountryTimestamp = storedTimestamp
        return storedCode
    }

    private func cacheDetectedCountry(_ isoCode: String) {
        let normalized = isoCode.uppercased()
        let timestamp = Date().timeIntervalSince1970
        cachedCountryCode = normalized
        cachedCountryTimestamp = timestamp
        userDefaults.set(normalized, forKey: StorageKeys.cachedDetectedCountryCode)
        userDefaults.set(timestamp, forKey: StorageKeys.cachedDetectedCountryTimestamp)
    }

    private func clearCachedDetectedCountry() {
        userDefaults.removeObject(forKey: StorageKeys.cachedDetectedCountryCode)
        userDefaults.removeObject(forKey: StorageKeys.cachedDetectedCountryTimestamp)
    }

    private func updateRecentCountries(with isoCode: String) {
        let normalized = isoCode.uppercased()
        var recentCodes = userDefaults.stringArray(forKey: StorageKeys.recentCountryCodes) ?? []
        recentCodes.removeAll { $0.uppercased() == normalized }
        recentCodes.insert(normalized, at: 0)

        if recentCodes.count > maxRecentCountries {
            recentCodes = Array(recentCodes.prefix(maxRecentCountries))
        }

        userDefaults.set(recentCodes, forKey: StorageKeys.recentCountryCodes)
    }
}

private final class LocationCountryDetector: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var continuation: CheckedContinuation<String?, Never>?
    private var timeoutTask: Task<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func detectCountry() async -> String? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.requestLocation()
            startTimeout()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            finish(nil)
            return
        }

        Task {
            do {
                let placemarks = try await geocoder.reverseGeocodeLocation(location)
                let isoCode = placemarks.first?.isoCountryCode?.uppercased()
                finish(isoCode)
            } catch {
                finish(nil)
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(nil)
    }

    private func startTimeout() {
        timeoutTask?.cancel()
        timeoutTask = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            finish(nil)
        }
    }

    private func finish(_ isoCode: String?) {
        timeoutTask?.cancel()
        timeoutTask = nil

        guard let continuation = continuation else { return }
        self.continuation = nil
        continuation.resume(returning: isoCode)
    }
}

// MARK: - Preview Helpers

#if DEBUG
extension CountryCodeData {
    static let preview = CountryCodeData(
        id: "HK",
        name: "Hong Kong",
        localizedName: "香港",
        dialCode: "+852",
        flag: "🇭🇰",
        phoneFormat: "XXXX XXXX",
        minLength: 8,
        maxLength: 8
    )
}
#endif
