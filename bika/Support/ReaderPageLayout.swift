import CoreGraphics
import Foundation
import Observation

/// Identifies a reader page across episode switches and page reuse.
///
/// The reader lists pages by index, so SwiftUI recycles a row when the episode changes. Keying
/// layout state by index would carry one episode's measurements into the next; keying by this
/// identity does not.
nonisolated struct ReaderPageID: Hashable, Sendable {
    let episodeID: String
    let backendPageID: String?
    let imageURL: URL
}

nonisolated enum ReaderVerticalImageLayout {
    static let fallbackPageHeight: CGFloat = 500
    static let fallbackAspectRatio: CGFloat = 1.5

    static func pageHeight(
        viewportWidth: CGFloat,
        exactAspectRatio: CGFloat?,
        estimatedAspectRatio: CGFloat?,
        fallbackAspectRatio: CGFloat = fallbackAspectRatio
    ) -> CGFloat {
        guard viewportWidth.isFinite, viewportWidth > 0 else { return fallbackPageHeight }

        if let exactAspectRatio,
           exactAspectRatio.isFinite,
           exactAspectRatio > 0 {
            return viewportWidth * exactAspectRatio
        }

        if let estimatedAspectRatio,
           estimatedAspectRatio.isFinite,
           estimatedAspectRatio > 0 {
            return viewportWidth * estimatedAspectRatio
        }

        let resolvedFallback = fallbackAspectRatio.isFinite && fallbackAspectRatio > 0
            ? fallbackAspectRatio
            : Self.fallbackAspectRatio
        return viewportWidth * resolvedFallback
    }
}

/// Owns everything the vertical reader needs to decide how tall a page is.
///
/// This used to live as four separate pieces of view state whose invariants — which pages are
/// samples, when the estimate is stale, what survives an episode change — were enforced by
/// guards scattered across the view body. Holding them together makes those rules checkable.
@Observable
final class ReaderPageLayoutStore {
    /// How many pages are averaged into the estimate used for pages not yet measured.
    static let sampleCount = 3

    /// Aspect ratio changes below this are treated as measurement noise and ignored, so a
    /// re-reported ratio does not churn the layout.
    static let aspectRatioTolerance: CGFloat = 0.0001

    private(set) var aspectRatios: [ReaderPageID: CGFloat] = [:]
    private(set) var estimatedAspectRatio: CGFloat?
    private(set) var sampledPageIDs: [ReaderPageID] = []

    func pageHeight(for pageID: ReaderPageID?, viewportWidth: CGFloat) -> CGFloat {
        ReaderVerticalImageLayout.pageHeight(
            viewportWidth: viewportWidth,
            exactAspectRatio: pageID.flatMap { aspectRatios[$0] },
            estimatedAspectRatio: estimatedAspectRatio
        )
    }

    /// - Returns: whether this changed the stored layout, so callers can tell a real
    ///   measurement from a repeat.
    @discardableResult
    func record(_ aspectRatio: CGFloat, for pageID: ReaderPageID) -> Bool {
        guard aspectRatio.isFinite, aspectRatio > 0 else { return false }

        if let previous = aspectRatios[pageID],
           abs(previous - aspectRatio) < Self.aspectRatioTolerance {
            return false
        }

        aspectRatios[pageID] = aspectRatio
        if sampledPageIDs.contains(pageID) {
            refreshEstimate()
        }
        return true
    }

    func record(_ aspectRatiosByPage: [ReaderPageID: CGFloat]) {
        for (pageID, aspectRatio) in aspectRatiosByPage {
            record(aspectRatio, for: pageID)
        }
    }

    /// Nominates a page to inform the estimate for pages that have not been measured yet.
    /// Only the first `sampleCount` distinct pages are taken.
    func registerSample(_ pageID: ReaderPageID) {
        guard sampledPageIDs.count < Self.sampleCount,
              !sampledPageIDs.contains(pageID) else {
            return
        }

        sampledPageIDs.append(pageID)
        refreshEstimate()
    }

    /// Measurements from one episode say nothing about the next.
    func reset() {
        aspectRatios = [:]
        sampledPageIDs = []
        estimatedAspectRatio = nil
    }

    private func refreshEstimate() {
        let ratios = sampledPageIDs.compactMap { aspectRatios[$0] }.sorted()
        guard !ratios.isEmpty else {
            estimatedAspectRatio = nil
            return
        }

        let middle = ratios.count / 2
        estimatedAspectRatio = ratios.count.isMultiple(of: 2)
            ? (ratios[middle - 1] + ratios[middle]) / 2
            : ratios[middle]
    }
}
