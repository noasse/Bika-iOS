import SwiftUI
import UIKit

@MainActor
@Observable
final class CachedAsyncImageLoadingState {
    private(set) var image: UIImage?
    private var loadingIdentity: String?

    static func cacheIdentity(
        url: URL?,
        targetSize: CGSize?,
        contentMode: ContentMode = .fit
    ) -> String {
        guard let url else { return "nil" }
        let target = decodeTarget(targetSize: targetSize, contentMode: contentMode)
        return ImageCache.cacheIdentity(for: url, target: target)
    }

    func load(
        url: URL?,
        targetSize: CGSize?,
        contentMode: ContentMode = .fit,
        purpose: ImageDiagnosticPurpose,
        imageLoader: any ImageDataLoading,
        imageCache: ImageCache,
        diagnostics: any ImageDiagnosticsRecording,
        onImageSize: ((CGSize) -> Void)?
    ) async {
        let identity = Self.cacheIdentity(
            url: url,
            targetSize: targetSize,
            contentMode: contentMode
        )
        loadingIdentity = identity

        guard let url else {
            image = nil
            loadingIdentity = nil
            return
        }

        let target = Self.decodeTarget(
            targetSize: targetSize,
            contentMode: contentMode
        )
        let diagnosticContext = ImageDiagnosticContext(
            purpose: purpose,
            url: url
        )

        image = nil

        do {
            let loaded = try await imageCache.loadAsset(
                for: url,
                target: target,
                imageLoader: imageLoader,
                diagnosticContext: diagnosticContext
            )
            try Task.checkCancellation()
            guard loadingIdentity == identity else {
                diagnostics.record(
                    Self.displayEvent(
                        context: diagnosticContext,
                        action: .cancelled,
                        error: CancellationError()
                    )
                )
                return
            }
            image = loaded.image
            onImageSize?(loaded.displaySize)
            loadingIdentity = nil
            diagnostics.record(
                Self.displayEvent(
                    context: diagnosticContext,
                    action: .succeeded
                )
            )
        } catch {
            diagnostics.record(
                Self.displayEvent(
                    context: diagnosticContext,
                    action: Self.isCancellation(error) ? .cancelled : .failed,
                    error: error
                )
            )
            guard loadingIdentity == identity else { return }
            image = nil
            loadingIdentity = nil
            // Auxiliary image requests can degrade to the placeholder without blocking the screen.
        }
    }

    private static func displayEvent(
        context: ImageDiagnosticContext,
        action: ImageDiagnosticAction,
        error: Error? = nil
    ) -> ImageDiagnosticEvent {
        ImageDiagnosticEvent(
            sequence: 0,
            timestamp: Date(),
            requestID: context.requestID,
            networkRequestID: nil,
            purpose: context.purpose,
            stage: .display,
            action: action,
            url: context.url,
            cacheIdentity: nil,
            httpStatus: nil,
            responseBytes: nil,
            durationMilliseconds: nil,
            retryAttempt: 0,
            decodeTarget: nil,
            sourcePixelSize: nil,
            decodedPixelSize: nil,
            error: error,
            metadata: ImageDiagnosticEventMetadata(
                pageStableID: context.pageStableID,
                contentType: nil,
                wasCachedResponse: nil
            )
        )
    }

    private static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError
            || (error as? URLError)?.code == .cancelled
    }

    private static func decodeTarget(
        targetSize: CGSize?,
        contentMode: ContentMode
    ) -> ImageDecodeTarget {
        guard let targetSize else { return .full }
        switch contentMode {
        case .fill:
            return .fill(targetSize)
        case .fit:
            return .fit(targetSize)
        @unknown default:
            return .fit(targetSize)
        }
    }
}

struct CachedAsyncImage<Placeholder: View>: View {
    let url: URL?
    var targetSize: CGSize? = nil
    var contentMode: ContentMode = .fit
    var imageLoader: any ImageDataLoading = AppDependencies.shared.imageDataLoader
    var imageCache: ImageCache = .shared
    var purpose: ImageDiagnosticPurpose = .unspecified
    var diagnostics: any ImageDiagnosticsRecording = ImageDiagnosticsService.shared
    var onImageSize: ((CGSize) -> Void)? = nil
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var loadingState = CachedAsyncImageLoadingState()

    var body: some View {
        ZStack {
            if let image = loadingState.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholder()
            }
        }
        .task(id: cacheIdentity) { await loadImage(for: cacheIdentity) }
    }

    private var cacheIdentity: String {
        CachedAsyncImageLoadingState.cacheIdentity(
            url: url,
            targetSize: targetSize,
            contentMode: contentMode
        )
    }

    private func loadImage(for _: String) async {
        await loadingState.load(
            url: url,
            targetSize: targetSize,
            contentMode: contentMode,
            purpose: purpose,
            imageLoader: imageLoader,
            imageCache: imageCache,
            diagnostics: diagnostics,
            onImageSize: onImageSize
        )
    }
}
