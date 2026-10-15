import AVFoundation
import UIKit

/// Shows a page's translations over its original text.
///
/// Lives inside the page's image view, so it zooms and pans with the page. Each translation
/// is its own small view — a cover in the bubble's tone and a label — rather than one drawing
/// of the whole page: covers stay sharp under zoom as they are, and only the labels are
/// re-rendered at the zoomed scale, so memory follows the text's area, not the page's.
final class MangaTranslationOverlayView: UIView {
    enum State: Equatable {
        case translating
        case translated(blocks: [MangaTextBlock], translations: [String], grounds: [Double])
        case failed(String)
    }

    var imageSize: CGSize = .zero { didSet { if imageSize != oldValue { invalidate() } } }
    var state: State = .translating { didSet { if state != oldValue { invalidate() } } }
    /// While true the page shows its original text; the translation stays ready underneath.
    var showsOriginal = false { didSet { isHidden = showsOriginal } }
    /// The page's zoom scale; labels render at it so text stays sharp when zoomed in.
    var zoomScale: CGFloat = 1 { didSet { if zoomScale != oldValue { applyTextScale() } } }

    private(set) var items: [MangaTranslationLayout.Item] = []
    private var labels: [UILabel] = []
    private var builtSize: CGSize?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isOpaque = false
        backgroundColor = .clear
        accessibilityIdentifier = "reader.translationOverlay"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if builtSize != bounds.size { rebuild() }
    }

    private func invalidate() {
        builtSize = nil
        setNeedsLayout()
    }

    private func rebuild() {
        builtSize = bounds.size
        subviews.forEach { $0.removeFromSuperview() }
        labels = []
        items = []
        guard imageSize.width > 0, imageSize.height > 0, bounds.width > 0, bounds.height > 0 else { return }
        // Where the image actually sits inside the image view.
        let imageRect = AVMakeRect(aspectRatio: imageSize, insideRect: bounds)

        switch state {
        case .translating:
            addBadge("翻译中…", at: imageRect.origin, color: UIColor.black.withAlphaComponent(0.55))
        case .failed(let message):
            addBadge(message, at: imageRect.origin, color: UIColor.systemRed.withAlphaComponent(0.85))
        case .translated(let blocks, let translations, let grounds):
            items = MangaTranslationLayout.items(blocks: blocks, translations: translations, grounds: grounds, in: imageRect)
            for item in items { add(item) }
        }
        applyTextScale()
    }

    private func add(_ item: MangaTranslationLayout.Item) {
        let cover = UIView(frame: item.cover)
        cover.backgroundColor = UIColor(white: item.coverLevel, alpha: item.coverAlpha)
        cover.layer.cornerRadius = item.cornerRadius
        cover.isUserInteractionEnabled = false
        addSubview(cover)

        let label = UILabel()
        label.attributedText = MangaTranslationLayout.attributed(item.text, size: item.fontSize, level: item.textLevel)
        label.numberOfLines = 0
        // A translation too long even at the smallest size is cut off rather than spilling
        // over the art.
        label.lineBreakMode = .byTruncatingTail
        label.textAlignment = .center
        let measured = MangaTranslationLayout.measuredSize(item.text, size: item.fontSize, width: item.textRect.width)
        let height = min(measured.height, item.textRect.height)
        label.frame = CGRect(x: item.textRect.minX, y: item.textRect.midY - height / 2, width: item.textRect.width, height: height)
        addSubview(label)
        labels.append(label)
    }

    private func addBadge(_ text: String, at origin: CGPoint, color: UIColor) {
        let label = PaddedLabel()
        label.text = text
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .white
        label.backgroundColor = color
        label.numberOfLines = 0
        let size = label.sizeThatFits(CGSize(width: 260, height: 200))
        label.frame = CGRect(origin: CGPoint(x: origin.x + 6, y: origin.y + 6), size: size)
        label.layer.cornerRadius = min(size.height / 2, 10)
        label.layer.masksToBounds = true
        addSubview(label)
        labels.append(label)
    }

    private func applyTextScale() {
        let screenScale = traitCollection.displayScale > 0 ? traitCollection.displayScale : 2
        // Capped: past this a label's backing store grows faster than it gets sharper.
        let scale = screenScale * min(max(zoomScale, 1), 4)
        for label in labels { label.layer.contentsScale = scale; label.setNeedsDisplay() }
    }
}

private final class PaddedLabel: UILabel {
    private let insets = UIEdgeInsets(top: 3, left: 8, bottom: 3, right: 8)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let inner = super.sizeThatFits(CGSize(width: size.width - insets.left - insets.right, height: size.height))
        return CGSize(width: ceil(inner.width) + insets.left + insets.right, height: ceil(inner.height) + insets.top + insets.bottom)
    }
}
