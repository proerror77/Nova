import Foundation
import Vision
import UIKit

// MARK: - Local Vision Service
// Uses Apple's Vision framework for on-device image analysis
// No network required - instant results

@MainActor
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

        var tags: [TagSuggestion] = []

        // Run classification
        let classificationTags = await classifyImage(cgImage)
        tags.append(contentsOf: classificationTags)

        // Detect text (for memes, screenshots, etc.)
        let textTags = await detectText(cgImage)
        tags.append(contentsOf: textTags)

        // Detect faces for portrait tagging
        let faceTags = await detectFaces(cgImage)
        tags.append(contentsOf: faceTags)

        // Sort by confidence and limit
        tags.sort { $0.confidence > $1.confidence }
        let limitedTags = Array(tags.prefix(15))

        let processingTime = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)

        #if DEBUG
        print("[LocalVision] Analyzed image in \(processingTime)ms, found \(limitedTags.count) tags")
        #endif

        return VLMAnalysisResult(
            tags: limitedTags,
            channels: nil,
            processingTimeMs: processingTime
        )
    }

    // MARK: - Vision Classification

    private func classifyImage(_ cgImage: CGImage) async -> [TagSuggestion] {
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
            #if DEBUG
            print("[LocalVision] Classification error: \(error)")
            #endif
            return []
        }
    }

    // MARK: - Text Detection

    private func detectText(_ cgImage: CGImage) async -> [TagSuggestion] {
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

    // MARK: - Face Detection

    private func detectFaces(_ cgImage: CGImage) async -> [TagSuggestion] {
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
