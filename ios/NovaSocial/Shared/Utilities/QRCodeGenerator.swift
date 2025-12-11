import SwiftUI
import CoreImage.CIFilterBuiltins

/// Utility for generating QR codes for user profiles
enum QRCodeGenerator {

    /// The URL scheme for Nova user profiles
    private static let userURLScheme = "nova://user/"

    /// Generate a QR code image for a user ID
    /// - Parameters:
    ///   - userId: The user's unique identifier
    ///   - size: The desired size of the QR code image (default: 200x200)
    /// - Returns: A UIImage containing the QR code, or nil if generation fails
    static func generateUserQRCode(userId: String, size: CGFloat = 200) -> UIImage? {
        let urlString = "\(userURLScheme)\(userId)"
        return generateQRCode(from: urlString, size: size)
    }

    /// Generate a QR code image from a string
    /// - Parameters:
    ///   - string: The string to encode
    ///   - size: The desired size of the QR code image
    /// - Returns: A UIImage containing the QR code, or nil if generation fails
    static func generateQRCode(from string: String, size: CGFloat = 200) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()

        guard let data = string.data(using: .utf8) else {
            return nil
        }

        filter.message = data
        filter.correctionLevel = "M" // Medium error correction

        guard let outputImage = filter.outputImage else {
            return nil
        }

        // Scale the image to the desired size
        let scaleX = size / outputImage.extent.size.width
        let scaleY = size / outputImage.extent.size.height
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }

    /// Parse a scanned QR code to extract user ID
    /// - Parameter scannedString: The string from the scanned QR code
    /// - Returns: The user ID if the QR code is a valid Nova user QR code, nil otherwise
    static func parseUserQRCode(_ scannedString: String) -> String? {
        // Check for nova:// scheme
        if scannedString.hasPrefix(userURLScheme) {
            let userId = String(scannedString.dropFirst(userURLScheme.count))
            return userId.isEmpty ? nil : userId
        }

        // Also support https://nova.social/user/{userId} format
        let webURLPrefix = "https://nova.social/user/"
        if scannedString.hasPrefix(webURLPrefix) {
            let userId = String(scannedString.dropFirst(webURLPrefix.count))
            return userId.isEmpty ? nil : userId
        }

        return nil
    }
}

// MARK: - SwiftUI Image Extension

extension QRCodeGenerator {
    /// Generate a SwiftUI Image for a user's QR code
    /// - Parameters:
    ///   - userId: The user's unique identifier
    ///   - size: The desired size of the QR code
    /// - Returns: A SwiftUI Image, or nil if generation fails
    static func userQRCodeImage(userId: String, size: CGFloat = 200) -> Image? {
        guard let uiImage = generateUserQRCode(userId: userId, size: size) else {
            return nil
        }
        return Image(uiImage: uiImage)
    }
}
