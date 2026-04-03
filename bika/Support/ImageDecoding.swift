import CoreGraphics
import ImageIO
import UIKit

nonisolated enum ImageDecoding {
    static func decodeImage(
        from data: Data,
        targetSize: CGSize? = nil,
        scale: CGFloat = 2,
        overscan: CGFloat = 1
    ) -> UIImage? {
        guard let targetSize, targetSize.width > 0, targetSize.height > 0 else {
            return UIImage(data: data)
        }

        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return UIImage(data: data)
        }

        let maxPixelSize = max(targetSize.width, targetSize.height) * scale * max(overscan, 1)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return UIImage(data: data)
        }

        return UIImage(cgImage: cgImage)
    }

    static func cacheCost(for image: UIImage) -> Int {
        if let cgImage = image.cgImage {
            return cgImage.bytesPerRow * cgImage.height
        }

        let pixelWidth = Int(image.size.width * image.scale)
        let pixelHeight = Int(image.size.height * image.scale)
        return pixelWidth * pixelHeight * 4
    }

    static func cacheKeySuffix(for targetSize: CGSize?) -> String {
        guard let targetSize, targetSize.width > 0, targetSize.height > 0 else { return "full" }
        return "\(Int(targetSize.width.rounded()))x\(Int(targetSize.height.rounded()))"
    }
}
