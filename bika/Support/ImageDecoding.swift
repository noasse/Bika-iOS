import CoreGraphics
import ImageIO
import UIKit

nonisolated enum ImageDecodeTarget: Sendable, Equatable {
    case full
    case fit(CGSize)
    case fill(CGSize)
    case fitWidth(CGFloat)

    var cacheKey: String {
        switch self {
        case .full:
            return "full"
        case .fit(let size):
            return "fit-\(Self.rounded(size.width))x\(Self.rounded(size.height))"
        case .fill(let size):
            return "fill-\(Self.rounded(size.width))x\(Self.rounded(size.height))"
        case .fitWidth(let width):
            return "width-\(Self.rounded(width))"
        }
    }

    private static func rounded(_ value: CGFloat) -> Int {
        guard value.isFinite, value > 0 else { return 0 }
        return Int(value.rounded())
    }
}

nonisolated struct DecodedImageAsset: @unchecked Sendable {
    let image: UIImage
    let displaySize: CGSize

    var layoutAspectRatio: CGFloat {
        let imageSize = image.size
        guard imageSize.width.isFinite,
              imageSize.height.isFinite,
              imageSize.width > 0,
              imageSize.height > 0 else {
            return 1
        }
        return imageSize.height / imageSize.width
    }
}

nonisolated enum ImageDecoding {
    private static let maximumThumbnailPixelSize: CGFloat = 16_384

    static func decodeImage(
        from data: Data,
        targetSize: CGSize? = nil,
        scale: CGFloat = 2,
        overscan: CGFloat = 1
    ) -> UIImage? {
        let target = targetSize.map(ImageDecodeTarget.fit) ?? .full
        return decodeAsset(
            from: data,
            target: target,
            scale: scale,
            overscan: overscan
        )?.image
    }

    static func decodeAsset(
        from data: Data,
        target: ImageDecodeTarget,
        scale: CGFloat = 2,
        overscan: CGFloat = 1
    ) -> DecodedImageAsset? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            guard let image = UIImage(data: data) else { return nil }
            return DecodedImageAsset(image: image, displaySize: image.size)
        }

        let sourceDisplaySize = displaySize(for: source)

        guard let maxPixelSize = thumbnailMaxPixelSize(
            target: target,
            displaySize: sourceDisplaySize,
            scale: scale,
            overscan: overscan
        ) else {
            guard let image = UIImage(data: data) else { return nil }
            return DecodedImageAsset(
                image: image,
                displaySize: sourceDisplaySize ?? image.size
            )
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            guard let image = UIImage(data: data) else { return nil }
            return DecodedImageAsset(
                image: image,
                displaySize: sourceDisplaySize ?? image.size
            )
        }

        let image = UIImage(cgImage: cgImage)
        return DecodedImageAsset(
            image: image,
            displaySize: sourceDisplaySize ?? image.size
        )
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
        targetSize.map(ImageDecodeTarget.fit)?.cacheKey ?? ImageDecodeTarget.full.cacheKey
    }

    private static func displaySize(for source: CGImageSource) -> CGSize? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = number(from: properties[kCGImagePropertyPixelWidth] ?? properties[kCGImagePropertyWidth]),
              let height = number(from: properties[kCGImagePropertyPixelHeight] ?? properties[kCGImagePropertyHeight]),
              width > 0,
              height > 0 else {
            return nil
        }

        let orientationValue = number(from: properties[kCGImagePropertyOrientation]).map(UInt32.init) ?? 1
        let orientation = CGImagePropertyOrientation(rawValue: orientationValue) ?? .up
        switch orientation {
        case .leftMirrored, .right, .rightMirrored, .left:
            return CGSize(width: height, height: width)
        default:
            return CGSize(width: width, height: height)
        }
    }

    private static func thumbnailMaxPixelSize(
        target: ImageDecodeTarget,
        displaySize: CGSize?,
        scale: CGFloat,
        overscan: CGFloat
    ) -> CGFloat? {
        let resolvedScale = scale.isFinite ? max(scale, 1) : 1
        let resolvedOverscan = overscan.isFinite ? max(overscan, 1) : 1
        let targetDimension: CGFloat

        switch target {
        case .full:
            return nil
        case .fit(let size):
            guard size.width.isFinite,
                  size.height.isFinite,
                  size.width > 0,
                  size.height > 0 else { return nil }
            targetDimension = scaledMaximumDimension(
                displaySize: displaySize,
                targetSize: size,
                fillsTarget: false
            )
        case .fill(let size):
            guard size.width.isFinite,
                  size.height.isFinite,
                  size.width > 0,
                  size.height > 0 else { return nil }
            targetDimension = scaledMaximumDimension(
                displaySize: displaySize,
                targetSize: size,
                fillsTarget: true
            )
        case .fitWidth(let width):
            guard width.isFinite, width > 0 else { return nil }
            if let displaySize, displaySize.width > 0, displaySize.height > 0 {
                targetDimension = max(width, width * displaySize.height / displaySize.width)
            } else {
                targetDimension = width
            }
        }

        return min(
            maximumThumbnailPixelSize,
            max(1, targetDimension * resolvedScale * resolvedOverscan)
        )
    }

    private static func scaledMaximumDimension(
        displaySize: CGSize?,
        targetSize: CGSize,
        fillsTarget: Bool
    ) -> CGFloat {
        guard let displaySize,
              displaySize.width > 0,
              displaySize.height > 0 else {
            return max(targetSize.width, targetSize.height)
        }

        let horizontalScale = targetSize.width / displaySize.width
        let verticalScale = targetSize.height / displaySize.height
        let contentScale = fillsTarget
            ? max(horizontalScale, verticalScale)
            : min(horizontalScale, verticalScale)
        return max(displaySize.width, displaySize.height) * contentScale
    }

    private static func number(from value: Any?) -> CGFloat? {
        if let number = value as? NSNumber {
            return CGFloat(number.doubleValue)
        }
        return nil
    }
}
