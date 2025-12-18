import Foundation
import Photos
import Vision
import UIKit

// MARK: - Photo Analysis Service
// Uses Vision framework to analyze user's photo library and extract interest signals
// Results are sent to ranking-service for profile building

@Observable
final class PhotoAnalysisService {
    static let shared = PhotoAnalysisService()

    private let apiClient = APIClient.shared

    // Analysis state
    private(set) var isAnalyzing = false
    private(set) var analyzedPhotoCount = 0
    private(set) var lastAnalysisDate: Date?

    // Vision requests
    private lazy var classificationRequest: VNClassifyImageRequest = {
        let request = VNClassifyImageRequest()
        request.revision = VNClassifyImageRequestRevision1
        return request
    }()

    private init() {
        loadLastAnalysisDate()
    }

    // MARK: - Public API

    /// Request photo library access and analyze recent photos
    /// - Parameters:
    ///   - maxPhotos: Maximum number of photos to analyze (default: 100)
    ///   - daysBack: How many days back to look for photos (default: 90)
    /// - Returns: Analysis result with detected themes
    @MainActor
    func analyzePhotoLibrary(
        maxPhotos: Int = 100,
        daysBack: Int = 90
    ) async throws -> PhotoAnalysisResult {
        // Check authorization
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else {
            throw PhotoAnalysisError.notAuthorized
        }

        isAnalyzing = true
        analyzedPhotoCount = 0

        defer {
            isAnalyzing = false
            lastAnalysisDate = Date()
            saveLastAnalysisDate()
        }

        #if DEBUG
        print("[PhotoAnalysis] Starting photo library analysis")
        print("[PhotoAnalysis] Max photos: \(maxPhotos), Days back: \(daysBack)")
        #endif

        // Fetch recent photos
        let photos = fetchRecentPhotos(maxCount: maxPhotos, daysBack: daysBack)

        guard !photos.isEmpty else {
            #if DEBUG
            print("[PhotoAnalysis] No photos found in the specified date range")
            #endif
            return PhotoAnalysisResult(
                detectedThemes: [],
                analyzedAt: Date(),
                photoCount: 0,
                source: .iOSVision
            )
        }

        #if DEBUG
        print("[PhotoAnalysis] Found \(photos.count) photos to analyze")
        #endif

        // Analyze photos and aggregate themes
        var themeCounter: [String: ThemeAccumulator] = [:]

        for asset in photos {
            if let themes = await analyzePhoto(asset: asset) {
                for theme in themes {
                    if var existing = themeCounter[theme.identifier] {
                        existing.photoCount += 1
                        existing.totalConfidence += theme.confidence
                        existing.maxConfidence = max(existing.maxConfidence, theme.confidence)
                        themeCounter[theme.identifier] = existing
                    } else {
                        themeCounter[theme.identifier] = ThemeAccumulator(
                            identifier: theme.identifier,
                            photoCount: 1,
                            totalConfidence: theme.confidence,
                            maxConfidence: theme.confidence
                        )
                    }
                }
                analyzedPhotoCount += 1
            }
        }

        // Convert to PhotoTheme array
        let detectedThemes = themeCounter.values
            .filter { $0.photoCount >= 2 } // At least 2 photos with this theme
            .map { accumulator -> PhotoTheme in
                let avgConfidence = accumulator.totalConfidence / Float(accumulator.photoCount)
                return PhotoTheme(
                    theme: mapVisionIdentifierToTheme(accumulator.identifier),
                    confidence: avgConfidence,
                    photoCount: accumulator.photoCount,
                    subCategories: getSubCategories(for: accumulator.identifier)
                )
            }
            .sorted { $0.confidence * Float($0.photoCount) > $1.confidence * Float($1.photoCount) }
            .prefix(20) // Top 20 themes

        let result = PhotoAnalysisResult(
            detectedThemes: Array(detectedThemes),
            analyzedAt: Date(),
            photoCount: analyzedPhotoCount,
            source: .iOSVision
        )

        #if DEBUG
        print("[PhotoAnalysis] Analysis complete")
        print("[PhotoAnalysis] Analyzed \(analyzedPhotoCount) photos")
        print("[PhotoAnalysis] Detected \(result.detectedThemes.count) themes")
        for theme in result.detectedThemes.prefix(5) {
            print("[PhotoAnalysis]   - \(theme.theme): \(String(format: "%.2f", theme.confidence)) (\(theme.photoCount) photos)")
        }
        #endif

        return result
    }

    /// Send analysis results to backend for profile building
    @MainActor
    func uploadAnalysisResults(_ result: PhotoAnalysisResult) async throws {
        guard !result.detectedThemes.isEmpty else {
            #if DEBUG
            print("[PhotoAnalysis] No themes to upload")
            #endif
            return
        }

        let request = PhotoAnalysisUploadRequest(
            detectedThemes: result.detectedThemes,
            analyzedAt: result.analyzedAt,
            photoCount: result.photoCount,
            source: result.source.rawValue
        )

        #if DEBUG
        print("[PhotoAnalysis] Uploading analysis results to backend")
        #endif

        let response: PhotoAnalysisUploadResponse = try await apiClient.request(
            endpoint: APIConfig.UserProfile.uploadPhotoAnalysis,
            method: "POST",
            body: request
        )

        #if DEBUG
        print("[PhotoAnalysis] Upload successful: \(response.interestsCreated) interests created")
        #endif
    }

    /// Analyze and upload in one call
    @MainActor
    func analyzeAndUpload(
        maxPhotos: Int = 100,
        daysBack: Int = 90
    ) async throws -> PhotoAnalysisResult {
        let result = try await analyzePhotoLibrary(maxPhotos: maxPhotos, daysBack: daysBack)
        try await uploadAnalysisResults(result)
        return result
    }

    /// Check if analysis should be run (e.g., hasn't been done recently)
    func shouldRunAnalysis(intervalDays: Int = 7) -> Bool {
        guard let lastDate = lastAnalysisDate else { return true }
        let daysSince = Calendar.current.dateComponents([.day], from: lastDate, to: Date()).day ?? 0
        return daysSince >= intervalDays
    }

    /// Upload onboarding interest selections to backend for profile building
    /// - Parameter selectedChannels: Array of channel/interest IDs selected during onboarding
    @MainActor
    func uploadOnboardingInterests(_ selectedChannels: [String]) async throws {
        guard !selectedChannels.isEmpty else {
            #if DEBUG
            print("[PhotoAnalysis] No channels to upload for onboarding")
            #endif
            return
        }

        let request = OnboardingInterestsUploadRequest(
            selectedChannels: selectedChannels,
            selectedAt: Date()
        )

        #if DEBUG
        print("[PhotoAnalysis] Uploading \(selectedChannels.count) onboarding interests to backend")
        #endif

        let response: OnboardingInterestsUploadResponse = try await apiClient.request(
            endpoint: APIConfig.UserProfile.uploadOnboardingInterests,
            method: "POST",
            body: request
        )

        #if DEBUG
        print("[PhotoAnalysis] Onboarding upload successful: \(response.interestsCreated) interests created")
        #endif
    }

    // MARK: - Private Methods

    private func fetchRecentPhotos(maxCount: Int, daysBack: Int) -> [PHAsset] {
        let fetchOptions = PHFetchOptions()

        // Only fetch images (not videos)
        fetchOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)

        // Sort by creation date, newest first
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        // Limit results
        fetchOptions.fetchLimit = maxCount

        // Filter by date
        let startDate = Calendar.current.date(byAdding: .day, value: -daysBack, to: Date())!
        fetchOptions.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue),
            NSPredicate(format: "creationDate >= %@", startDate as NSDate)
        ])

        let fetchResult = PHAsset.fetchAssets(with: fetchOptions)

        var assets: [PHAsset] = []
        fetchResult.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }

        return assets
    }

    private func analyzePhoto(asset: PHAsset) async -> [VisionClassification]? {
        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .exact
            options.isSynchronous = false
            options.isNetworkAccessAllowed = true

            // Request a reasonable size for classification
            let targetSize = CGSize(width: 512, height: 512)

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { [weak self] image, info in
                guard let self = self, let image = image else {
                    continuation.resume(returning: nil)
                    return
                }

                // Check if this is the degraded (thumbnail) image
                if let isDegraded = info?[PHImageResultIsDegradedKey] as? Bool, isDegraded {
                    return // Wait for full quality image
                }

                let classifications = self.classifyImage(image)
                continuation.resume(returning: classifications)
            }
        }
    }

    private func classifyImage(_ image: UIImage) -> [VisionClassification]? {
        guard let cgImage = image.cgImage else { return nil }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([classificationRequest])

            guard let observations = classificationRequest.results else {
                return nil
            }

            // Filter by confidence threshold and take top results
            let classifications = observations
                .filter { $0.confidence > 0.3 } // Minimum 30% confidence
                .prefix(10) // Top 10 per image
                .map { VisionClassification(identifier: $0.identifier, confidence: $0.confidence) }

            return Array(classifications)
        } catch {
            #if DEBUG
            print("[PhotoAnalysis] Classification error: \(error)")
            #endif
            return nil
        }
    }

    private func mapVisionIdentifierToTheme(_ identifier: String) -> String {
        // Map Vision's technical identifiers to user-friendly theme names
        let mappings: [String: String] = [
            // Food & Drink
            "food": "food",
            "drink": "food",
            "coffee": "food",
            "wine": "food",
            "beer": "food",
            "restaurant": "food",
            "cooking": "food",

            // Travel & Places
            "beach": "travel",
            "mountain": "travel",
            "city": "travel",
            "architecture": "travel",
            "landmark": "travel",
            "hotel": "travel",
            "airplane": "travel",
            "train": "travel",

            // Fitness & Health
            "gym": "fitness",
            "workout": "fitness",
            "running": "fitness",
            "yoga": "fitness",
            "sports": "fitness",
            "exercise": "fitness",

            // Nature & Outdoors
            "nature": "nature",
            "forest": "nature",
            "garden": "nature",
            "flower": "nature",
            "plant": "nature",
            "sunset": "nature",
            "sunrise": "nature",
            "sky": "nature",

            // Animals & Pets
            "dog": "pets",
            "cat": "pets",
            "animal": "pets",
            "bird": "pets",
            "fish": "pets",

            // Art & Culture
            "art": "art",
            "museum": "art",
            "painting": "art",
            "sculpture": "art",
            "music": "art",
            "concert": "art",

            // Fashion & Style
            "fashion": "fashion",
            "clothing": "fashion",
            "shoes": "fashion",
            "accessories": "fashion",
            "makeup": "fashion",

            // Technology
            "computer": "technology",
            "phone": "technology",
            "electronics": "technology",
            "gadget": "technology",

            // Home & Interior
            "home": "lifestyle",
            "interior": "lifestyle",
            "furniture": "lifestyle",
            "decoration": "lifestyle",

            // Social & Events
            "party": "social",
            "celebration": "social",
            "wedding": "social",
            "birthday": "social",

            // Cars & Vehicles
            "car": "automotive",
            "motorcycle": "automotive",
            "vehicle": "automotive",
        ]

        // Try exact match first
        if let mapped = mappings[identifier.lowercased()] {
            return mapped
        }

        // Try partial match
        for (key, value) in mappings {
            if identifier.lowercased().contains(key) {
                return value
            }
        }

        // Return cleaned up identifier as fallback
        return identifier.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func getSubCategories(for identifier: String) -> [String] {
        // Return related sub-categories based on Vision identifier
        let subCategoryMap: [String: [String]] = [
            "food": ["cooking", "restaurant", "cuisine"],
            "travel": ["adventure", "vacation", "sightseeing"],
            "fitness": ["gym", "workout", "health"],
            "nature": ["outdoor", "landscape", "wildlife"],
            "pets": ["animals", "dogs", "cats"],
            "art": ["creative", "design", "culture"],
            "fashion": ["style", "beauty", "shopping"],
            "technology": ["gadgets", "innovation", "digital"],
            "social": ["events", "friends", "celebration"],
            "automotive": ["cars", "driving", "vehicles"],
        ]

        let theme = mapVisionIdentifierToTheme(identifier)
        return subCategoryMap[theme] ?? []
    }

    // MARK: - Persistence

    private func loadLastAnalysisDate() {
        lastAnalysisDate = UserDefaults.standard.object(forKey: "PhotoAnalysis.lastAnalysisDate") as? Date
    }

    private func saveLastAnalysisDate() {
        UserDefaults.standard.set(lastAnalysisDate, forKey: "PhotoAnalysis.lastAnalysisDate")
    }
}

// MARK: - Supporting Types

private struct ThemeAccumulator {
    var identifier: String
    var photoCount: Int
    var totalConfidence: Float
    var maxConfidence: Float
}

private struct VisionClassification {
    let identifier: String
    let confidence: Float
}

// MARK: - API Models (matching backend Rust structs)

/// Result from photo analysis - matches backend PhotoAnalysisResult
struct PhotoAnalysisResult: Codable {
    let detectedThemes: [PhotoTheme]
    let analyzedAt: Date
    let photoCount: Int
    let source: PhotoAnalysisSource

    enum CodingKeys: String, CodingKey {
        case detectedThemes = "detected_themes"
        case analyzedAt = "analyzed_at"
        case photoCount = "photo_count"
        case source
    }
}

/// A theme detected from photos - matches backend PhotoTheme
struct PhotoTheme: Codable {
    let theme: String
    let confidence: Float
    let photoCount: Int
    let subCategories: [String]

    enum CodingKeys: String, CodingKey {
        case theme
        case confidence
        case photoCount = "photo_count"
        case subCategories = "sub_categories"
    }
}

/// Source of photo analysis - matches backend PhotoAnalysisSource
enum PhotoAnalysisSource: String, Codable {
    case iOSVision = "ios_vision"
    case serverML = "server_ml"
    case combined = "combined"
}

/// Request to upload photo analysis results
private struct PhotoAnalysisUploadRequest: Codable {
    let detectedThemes: [PhotoTheme]
    let analyzedAt: Date
    let photoCount: Int
    let source: String

    enum CodingKeys: String, CodingKey {
        case detectedThemes = "detected_themes"
        case analyzedAt = "analyzed_at"
        case photoCount = "photo_count"
        case source
    }
}

/// Response from photo analysis upload
struct PhotoAnalysisUploadResponse: Codable {
    let success: Bool
    let interestsCreated: Int
    let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case success
        case interestsCreated = "interests_created"
        case errorMessage = "error_message"
    }
}

/// Request to upload onboarding interest selections
private struct OnboardingInterestsUploadRequest: Codable {
    let selectedChannels: [String]
    let selectedAt: Date

    enum CodingKeys: String, CodingKey {
        case selectedChannels = "selected_channels"
        case selectedAt = "selected_at"
    }
}

/// Response from onboarding interests upload
struct OnboardingInterestsUploadResponse: Codable {
    let success: Bool
    let interestsCreated: Int
    let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case success
        case interestsCreated = "interests_created"
        case errorMessage = "error_message"
    }
}

// MARK: - Errors

enum PhotoAnalysisError: LocalizedError {
    case notAuthorized
    case noPhotosFound
    case analysisFailed
    case uploadFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Photo library access not authorized. Please enable access in Settings."
        case .noPhotosFound:
            return "No photos found to analyze."
        case .analysisFailed:
            return "Failed to analyze photos."
        case .uploadFailed(let reason):
            return "Failed to upload analysis: \(reason)"
        }
    }
}
