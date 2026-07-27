import CoreGraphics

nonisolated enum ReaderViewportUpdate {
    static func shouldApply(currentSize: CGSize, newSize: CGSize) -> Bool {
        guard newSize.width.isFinite,
              newSize.height.isFinite,
              newSize.width > 0,
              newSize.height > 0 else {
            return false
        }

        if currentSize == .zero {
            return true
        }

        return abs(currentSize.width - newSize.width) >= 1
            || abs(currentSize.height - newSize.height) >= 1
    }
}
