import Foundation
import ImageIO
import UniformTypeIdentifiers

final class GuideImagePipeline: @unchecked Sendable {
    static let shared = GuideImagePipeline()

    private let cache = NSCache<NSString, NSData>()

    private init() {
        cache.countLimit = 96
        cache.totalCostLimit = 48 * 1024 * 1024
    }

    func imageData(for url: URL, maxPixelSize: Int) async throws -> Data {
        let cacheKey = "\(url.absoluteString)|\(maxPixelSize)" as NSString
        if let cachedData = cache.object(forKey: cacheKey) {
            return cachedData as Data
        }

        let (downloadedData, response) = try await URLSession.shared.data(from: url)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw GuideImagePipelineError.badResponse
        }

        let imageData = try await GuideImagePipeline.downsample(downloadedData, maxPixelSize: maxPixelSize)
        cache.setObject(imageData as NSData, forKey: cacheKey, cost: imageData.count)
        return imageData
    }

    private static func downsample(_ data: Data, maxPixelSize: Int) async throws -> Data {
        try await Task.detached(priority: .utility) {
            let sourceOptions: [CFString: Any] = [
                kCGImageSourceShouldCache: false,
            ]
            guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else {
                throw GuideImagePipelineError.decodeFailed
            }

            let thumbnailOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            ]
            guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
                throw GuideImagePipelineError.decodeFailed
            }

            let outputData = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(
                outputData,
                UTType.jpeg.identifier as CFString,
                1,
                nil
            ) else {
                throw GuideImagePipelineError.encodeFailed
            }

            let properties: [CFString: Any] = [
                kCGImageDestinationLossyCompressionQuality: 0.82,
            ]
            CGImageDestinationAddImage(destination, thumbnail, properties as CFDictionary)
            guard CGImageDestinationFinalize(destination) else {
                throw GuideImagePipelineError.encodeFailed
            }

            return outputData as Data
        }.value
    }
}

private enum GuideImagePipelineError: Error {
    case badResponse
    case decodeFailed
    case encodeFailed
}
