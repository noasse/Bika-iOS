import Foundation

/// A speech bubble found on a page: a white region and the ink enclosed by it.
nonisolated struct DetectedBubble: Sendable {
    /// Bounding box of the bubble's white interior.
    let bounds: PixelRect
    /// Bounding box of the ink inside the bubble.
    let inkBounds: PixelRect
    /// Ink mask over `bounds`, row-major, `true` for text pixels.
    let inkMask: [Bool]

    func isInk(x: Int, y: Int) -> Bool {
        guard x >= bounds.minX, x < bounds.maxX, y >= bounds.minY, y < bounds.maxY else { return false }
        return inkMask[(y - bounds.minY) * bounds.width + (x - bounds.minX)]
    }
}

/// Finds speech bubbles by their shape rather than by their text.
///
/// Vision does not detect vertical Japanese at all — not even as text rectangles — so the
/// pipeline cannot ask it where the text is. Bubbles are found instead as enclosed white
/// regions: a connected area of light pixels that does not touch the page edge. The text is
/// whatever dark pixels that area surrounds — the holes in it.
nonisolated struct SpeechBubbleDetector: Sendable {
    nonisolated struct Configuration: Sendable {
        /// Pixels at or above this are bubble interior.
        var lightThreshold: UInt8 = 200
        /// Holes darker than this count as ink.
        var inkThreshold: UInt8 = 160
        /// Bubble area as a fraction of the page.
        var minimumAreaFraction: Double = 0.002
        var maximumAreaFraction: Double = 0.35
        /// Bubbles are compact; long thin white strips are panel gutters.
        var minimumFillRatio: Double = 0.30
        /// Ink as a fraction of the bubble area. Below: an empty shape. Above: not a bubble.
        var minimumInkFraction: Double = 0.003
        var maximumInkFraction: Double = 0.55

        init() {}
    }

    var configuration = Configuration()

    func detect(in bitmap: GrayscaleBitmap) -> [DetectedBubble] {
        let width = bitmap.width
        let height = bitmap.height
        let pageArea = Double(width * height)
        let lightThreshold = configuration.lightThreshold

        // Label 4-connected light regions. 0 = unlabelled / not light.
        var labels = [Int32](repeating: 0, count: width * height)
        var components: [(label: Int32, bounds: PixelRect, area: Int, touchesEdge: Bool)] = []
        var stack: [Int] = []
        var nextLabel: Int32 = 1

        bitmap.pixels.withUnsafeBufferPointer { pixels in
            labels.withUnsafeMutableBufferPointer { labels in
                for start in 0..<(width * height) where labels[start] == 0 && pixels[start] >= lightThreshold {
                    let label = nextLabel
                    nextLabel += 1
                    labels[start] = label
                    stack.removeAll(keepingCapacity: true)
                    stack.append(start)
                    var bounds = PixelRect(minX: start % width, minY: start / width, maxX: start % width + 1, maxY: start / width + 1)
                    var area = 0
                    var touchesEdge = false
                    while let index = stack.popLast() {
                        area += 1
                        let x = index % width
                        let y = index / width
                        if x == 0 || y == 0 || x == width - 1 || y == height - 1 { touchesEdge = true }
                        bounds.minX = min(bounds.minX, x)
                        bounds.minY = min(bounds.minY, y)
                        bounds.maxX = max(bounds.maxX, x + 1)
                        bounds.maxY = max(bounds.maxY, y + 1)
                        if x > 0 { Self.visit(index - 1, pixels, labels, label, lightThreshold, &stack) }
                        if x < width - 1 { Self.visit(index + 1, pixels, labels, label, lightThreshold, &stack) }
                        if y > 0 { Self.visit(index - width, pixels, labels, label, lightThreshold, &stack) }
                        if y < height - 1 { Self.visit(index + width, pixels, labels, label, lightThreshold, &stack) }
                    }
                    components.append((label, bounds, area, touchesEdge))
                }
            }
        }

        var bubbles: [DetectedBubble] = []
        for component in components {
            // The page background and gutters reach the edge; bubbles are enclosed.
            guard !component.touchesEdge else { continue }
            let areaFraction = Double(component.area) / pageArea
            guard areaFraction >= configuration.minimumAreaFraction,
                  areaFraction <= configuration.maximumAreaFraction else { continue }
            guard Double(component.area) / Double(component.bounds.area) >= configuration.minimumFillRatio else { continue }

            guard let bubble = enclosedInk(
                of: component.label,
                bounds: component.bounds,
                bitmap: bitmap,
                labels: labels
            ) else { continue }
            bubbles.append(bubble)
        }
        return bubbles
    }

    private static func visit(
        _ index: Int,
        _ pixels: UnsafeBufferPointer<UInt8>,
        _ labels: UnsafeMutableBufferPointer<Int32>,
        _ label: Int32,
        _ threshold: UInt8,
        _ stack: inout [Int]
    ) {
        guard labels[index] == 0, pixels[index] >= threshold else { return }
        labels[index] = label
        stack.append(index)
    }

    /// The ink a region encloses: pixels inside its bounding box that are not part of it and
    /// cannot reach the box edge without crossing it. Pixels outside the bubble outline can
    /// reach the edge; the text strokes inside it cannot.
    private func enclosedInk(
        of label: Int32,
        bounds: PixelRect,
        bitmap: GrayscaleBitmap,
        labels: [Int32]
    ) -> DetectedBubble? {
        let boxWidth = bounds.width
        let boxHeight = bounds.height
        var outside = [Bool](repeating: false, count: boxWidth * boxHeight)
        var stack: [Int] = []

        func local(_ x: Int, _ y: Int) -> Int { (y - bounds.minY) * boxWidth + (x - bounds.minX) }
        func isRegion(_ x: Int, _ y: Int) -> Bool { labels[y * bitmap.width + x] == label }

        func seed(_ x: Int, _ y: Int) {
            let index = local(x, y)
            guard !outside[index], !isRegion(x, y) else { return }
            outside[index] = true
            stack.append(index)
        }
        for x in bounds.minX..<bounds.maxX {
            seed(x, bounds.minY)
            seed(x, bounds.maxY - 1)
        }
        for y in bounds.minY..<bounds.maxY {
            seed(bounds.minX, y)
            seed(bounds.maxX - 1, y)
        }
        while let index = stack.popLast() {
            let x = index % boxWidth + bounds.minX
            let y = index / boxWidth + bounds.minY
            if x > bounds.minX { seed(x - 1, y) }
            if x < bounds.maxX - 1 { seed(x + 1, y) }
            if y > bounds.minY { seed(x, y - 1) }
            if y < bounds.maxY - 1 { seed(x, y + 1) }
        }

        var mask = [Bool](repeating: false, count: boxWidth * boxHeight)
        var inkCount = 0
        var inkBounds: PixelRect?
        for y in bounds.minY..<bounds.maxY {
            for x in bounds.minX..<bounds.maxX {
                let index = local(x, y)
                // Light holes are counters inside glyphs (the middle of 口), not ink.
                guard !outside[index], !isRegion(x, y), bitmap[x, y] < configuration.inkThreshold else { continue }
                mask[index] = true
                inkCount += 1
                let pixel = PixelRect(minX: x, minY: y, maxX: x + 1, maxY: y + 1)
                inkBounds = inkBounds.map { $0.union(pixel) } ?? pixel
            }
        }

        let inkFraction = Double(inkCount) / Double(bounds.area)
        guard let inkBounds,
              inkFraction >= configuration.minimumInkFraction,
              inkFraction <= configuration.maximumInkFraction else {
            return nil
        }
        return DetectedBubble(bounds: bounds, inkBounds: inkBounds, inkMask: mask)
    }
}
