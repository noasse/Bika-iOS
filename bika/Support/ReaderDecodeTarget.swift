import CoreGraphics

/// Single source of truth for the size the reader decodes images at.
///
/// The reader has two consumers of that size — the prefetcher and the visible page — and they
/// previously derived it from different geometry. The prefetcher measured the safe-area-inset
/// container while the visible page measured its own `UIScrollView` bounds, which ignore the
/// safe area. Because `ImageDecodeTarget.cacheKey` is part of the cache key, the two produced
/// different entries and every page was fetched and decoded twice.
///
/// Both consumers now resolve their target here, from one measured content size.
nonisolated enum ReaderDecodeTargetResolver {
    /// - Parameter contentSize: size of the region pages are actually rendered into, measured
    ///   *after* safe-area expansion — the same box the page view fills.
    /// - Returns: `nil` when the content size is not yet usable, meaning no decode should be
    ///   requested at all. Callers must not substitute a fallback size; a guessed target is
    ///   what splits the cache in the first place.
    static func target(
        mode: ReaderViewModel.ReaderMode,
        contentSize: CGSize
    ) -> ImageDecodeTarget? {
        guard contentSize.width.isFinite, contentSize.width > 0 else { return nil }

        switch mode {
        case .horizontal:
            // A page spans the full viewport and is fitted inside it, so height matters.
            guard contentSize.height.isFinite, contentSize.height > 0 else { return nil }
            return .fit(contentSize)

        case .vertical:
            // Pages are laid out edge-to-edge and scroll freely; only width constrains them.
            return .fitWidth(contentSize.width)
        }
    }
}
