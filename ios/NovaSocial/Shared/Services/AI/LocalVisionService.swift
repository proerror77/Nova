import Foundation
import Vision
import UIKit

// MARK: - Local Vision Service
// Uses Apple's Vision framework for on-device image analysis
// No network required - instant results

final class LocalVisionService {
    static let shared = LocalVisionService()

    private init() {}

    // MARK: - Image Classification

    /// Analyze image locally using Vision framework
    /// - Parameter image: UIImage to analyze
    /// - Returns: VLM analysis result with tags
    func analyzeImage(_ image: UIImage) async -> VLMAnalysisResult {
        let startTime = CFAbsoluteTimeGetCurrent()

        guard let cgImage = image.cgImage else {
            return VLMAnalysisResult(tags: [], channels: nil, processingTimeMs: 0)
        }

        // Run Vision requests on background thread to avoid blocking UI
        let tags: [TagSuggestion] = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var allTags: [TagSuggestion] = []

                // Run classification
                let classificationTags = self.classifyImageSync(cgImage)
                allTags.append(contentsOf: classificationTags)

                // Detect text (for memes, screenshots, etc.)
                let textTags = self.detectTextSync(cgImage)
                allTags.append(contentsOf: textTags)

                // Detect faces for portrait tagging
                let faceTags = self.detectFacesSync(cgImage)
                allTags.append(contentsOf: faceTags)

                // Sort by confidence and limit
                allTags.sort { $0.confidence > $1.confidence }
                let limitedTags = Array(allTags.prefix(15))

                continuation.resume(returning: limitedTags)
            }
        }

        let processingTime = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)

        return VLMAnalysisResult(
            tags: tags,
            channels: nil,
            processingTimeMs: processingTime
        )
    }

    // MARK: - Vision Classification (Sync - runs on background thread)

    private func classifyImageSync(_ cgImage: CGImage) -> [TagSuggestion] {
        #if targetEnvironment(simulator)
        // VNClassifyImageRequest doesn't work on simulator (no Neural Engine)
        // Return basic tags based on image properties
        return simulatorFallbackTags(cgImage)
        #else
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request = VNClassifyImageRequest()

        do {
            try handler.perform([request])

            guard let observations = request.results else {
                return []
            }

            // Filter by confidence and blocklist
            let tags = observations
                .filter { $0.confidence >= 0.3 }
                .prefix(10)
                .compactMap { observation -> TagSuggestion? in
                    let tag = formatTag(observation.identifier)
                    guard !isBlocklisted(tag) else { return nil }
                    return TagSuggestion(
                        tag: tag,
                        confidence: observation.confidence,
                        source: "vision"
                    )
                }

            return Array(tags)
        } catch {
            return []
        }
        #endif
    }

    /// Fallback for simulator - basic image analysis without Neural Engine
    private func simulatorFallbackTags(_ cgImage: CGImage) -> [TagSuggestion] {
        var tags: [TagSuggestion] = []

        // Analyze image dimensions for aspect ratio hints
        let width = cgImage.width
        let height = cgImage.height
        let aspectRatio = Double(width) / Double(height)

        if aspectRatio > 1.5 {
            tags.append(TagSuggestion(tag: "Landscape", confidence: 0.7, source: "vision"))
        } else if aspectRatio < 0.7 {
            tags.append(TagSuggestion(tag: "Portrait", confidence: 0.7, source: "vision"))
        } else {
            tags.append(TagSuggestion(tag: "Square", confidence: 0.6, source: "vision"))
        }

        // Add generic photo tag
        tags.append(TagSuggestion(tag: "Photo", confidence: 0.8, source: "vision"))

        // High resolution hint
        if width > 2000 || height > 2000 {
            tags.append(TagSuggestion(tag: "HighRes", confidence: 0.6, source: "vision"))
        }

        return tags
    }

    // MARK: - Text Detection (Sync)

    private func detectTextSync(_ cgImage: CGImage) -> [TagSuggestion] {
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast

        do {
            try handler.perform([request])

            guard let observations = request.results else {
                return []
            }

            // If significant text found, add "text" or "quote" tag
            let textCount = observations.count
            var tags: [TagSuggestion] = []

            if textCount > 3 {
                tags.append(TagSuggestion(tag: "Text", confidence: 0.7, source: "vision"))
            }
            if textCount > 10 {
                tags.append(TagSuggestion(tag: "Screenshot", confidence: 0.6, source: "vision"))
            }

            return tags
        } catch {
            return []
        }
    }

    // MARK: - Face Detection (Sync)

    private func detectFacesSync(_ cgImage: CGImage) -> [TagSuggestion] {
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request = VNDetectFaceRectanglesRequest()

        do {
            try handler.perform([request])

            guard let observations = request.results else {
                return []
            }

            var tags: [TagSuggestion] = []
            let faceCount = observations.count

            if faceCount == 1 {
                tags.append(TagSuggestion(tag: "Portrait", confidence: 0.75, source: "vision"))
                tags.append(TagSuggestion(tag: "Selfie", confidence: 0.6, source: "vision"))
            } else if faceCount == 2 {
                tags.append(TagSuggestion(tag: "Couple", confidence: 0.65, source: "vision"))
            } else if faceCount >= 3 {
                tags.append(TagSuggestion(tag: "Group", confidence: 0.7, source: "vision"))
                tags.append(TagSuggestion(tag: "Friends", confidence: 0.55, source: "vision"))
            }

            return tags
        } catch {
            return []
        }
    }

    // MARK: - Helpers

    /// Format Vision identifier to user-friendly tag
    private func formatTag(_ identifier: String) -> String {
        // Vision returns identifiers like "outdoor_mountain" -> "Mountain"
        let parts = identifier.split(separator: "_")
        if let last = parts.last {
            return String(last).capitalized
        }
        return identifier.capitalized
    }

    /// Check if tag is too generic
    private func isBlocklisted(_ tag: String) -> Bool {
        let blocklist = Set([
            "image", "photo", "picture", "screenshot", "snapshot", "photography",
            "person", "people", "human", "man", "woman", "adult", "child",
            "day", "night", "indoor", "outdoor", "daytime",
            "closeup", "background", "foreground", "horizontal", "vertical"
        ])
        return blocklist.contains(tag.lowercased())
    }
}
