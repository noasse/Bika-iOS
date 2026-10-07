#if DEBUG
import AVFoundation
import UIKit

/// Draws what the translation pipeline found on a page: bubbles, the lines inside them, and
/// the text Vision read. Debug builds only — it exists so recognition can be judged on real
/// raw pages on a device, which the synthetic test pages cannot stand in for.
///
/// Lives inside the page's image view, so it zooms and pans with the page.
final class MangaTextDebugOverlayView: UIView {
    enum State {
        case idle
        case recognising
        case finished(blocks: [MangaTextBlock], milliseconds: Int)
        case failed(String)
    }

    var imageSize: CGSize = .zero { didSet { setNeedsDisplay() } }
    var state: State = .idle { didSet { setNeedsDisplay() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func draw(_ rect: CGRect) {
        guard imageSize.width > 0, imageSize.height > 0 else { return }
        // Where the image actually sits inside the image view.
        let imageRect = AVMakeRect(aspectRatio: imageSize, insideRect: bounds)

        switch state {
        case .idle:
            return
        case .recognising:
            drawBadge("识别中…", at: imageRect.origin)
        case .failed(let message):
            drawBadge("识别失败：\(message)", at: imageRect.origin, color: .systemRed)
        case .finished(let blocks, let milliseconds):
            drawBadge("\(blocks.count) 个对话框 · \(milliseconds) ms", at: imageRect.origin)
            for (index, block) in blocks.enumerated() {
                draw(block, number: index + 1, in: imageRect)
            }
        }
    }

    private func draw(_ block: MangaTextBlock, number: Int, in imageRect: CGRect) {
        func onScreen(_ rect: NormalizedRect) -> CGRect {
            rect.rect(in: imageRect.size).offsetBy(dx: imageRect.minX, dy: imageRect.minY)
        }

        let bubble = UIBezierPath(rect: onScreen(block.bubble))
        bubble.lineWidth = 2
        UIColor.systemBlue.setStroke()
        bubble.stroke()

        UIColor.systemRed.withAlphaComponent(0.8).setStroke()
        for (lineIndex, line) in block.lines.enumerated() {
            let path = UIBezierPath(rect: onScreen(line))
            path.lineWidth = 1.5
            path.stroke()
            // Reading order of lines, so a wrong order is visible at a glance.
            label("\(lineIndex + 1)", at: CGPoint(x: onScreen(line).midX - 4, y: onScreen(line).minY - 12),
                  size: 9, color: .systemRed, background: .clear)
        }

        let marker = block.orientation == .vertical ? "縦" : "横"
        let text = "\(number) \(marker) \(block.sourceText)"
        let bubbleRect = onScreen(block.bubble)
        label(text, at: CGPoint(x: bubbleRect.minX, y: bubbleRect.maxY + 2), size: 11,
              color: .white, background: UIColor.black.withAlphaComponent(0.75), maxWidth: max(bubbleRect.width, 160))
    }

    private func drawBadge(_ text: String, at origin: CGPoint, color: UIColor = .systemBlue) {
        label(text, at: CGPoint(x: origin.x + 6, y: origin.y + 6), size: 12,
              color: .white, background: color.withAlphaComponent(0.85))
    }

    private func label(_ text: String, at origin: CGPoint, size: CGFloat, color: UIColor,
                       background: UIColor, maxWidth: CGFloat = 320) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: size, weight: .semibold),
            .foregroundColor: color,
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let textSize = string.boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            context: nil
        ).size
        let box = CGRect(origin: origin, size: CGSize(width: ceil(textSize.width) + 8, height: ceil(textSize.height) + 4))
        background.setFill()
        UIBezierPath(roundedRect: box, cornerRadius: 4).fill()
        string.draw(with: box.insetBy(dx: 4, dy: 2), options: [.usesLineFragmentOrigin], context: nil)
    }
}
#endif
