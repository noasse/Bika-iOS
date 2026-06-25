import AppKit
import SwiftUI

struct MacReaderKeyboardBridge: NSViewRepresentable {
    var isEnabled = true
    let onLeft: () -> Void
    let onRight: () -> Void

    func makeNSView(context: Context) -> KeyView {
        let view = KeyView()
        view.isEnabled = isEnabled
        view.onLeft = onLeft
        view.onRight = onRight
        return view
    }

    func updateNSView(_ nsView: KeyView, context: Context) {
        nsView.isEnabled = isEnabled
        nsView.onLeft = onLeft
        nsView.onRight = onRight
        guard isEnabled else { return }
        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }

    final class KeyView: NSView {
        var isEnabled = true
        var onLeft: (() -> Void)?
        var onRight: (() -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async {
                self.window?.makeFirstResponder(self)
            }
        }

        override func keyDown(with event: NSEvent) {
            guard isEnabled else {
                super.keyDown(with: event)
                return
            }

            switch event.keyCode {
            case 123:
                onLeft?()
            case 124:
                onRight?()
            default:
                super.keyDown(with: event)
            }
        }
    }
}

struct MacHorizontalScrollBridge: NSViewRepresentable {
    var isEnabled = true
    let onPrevious: () -> Void
    let onNext: () -> Void

    func makeNSView(context: Context) -> ScrollView {
        let view = ScrollView()
        view.isEnabled = isEnabled
        view.onPrevious = onPrevious
        view.onNext = onNext
        return view
    }

    func updateNSView(_ nsView: ScrollView, context: Context) {
        nsView.isEnabled = isEnabled
        nsView.onPrevious = onPrevious
        nsView.onNext = onNext
    }

    final class ScrollView: NSView {
        var isEnabled = true {
            didSet {
                if !isEnabled {
                    accumulatedDeltaX = 0
                    triggeredInCurrentGesture = false
                }
            }
        }
        var onPrevious: (() -> Void)?
        var onNext: (() -> Void)?

        private var accumulatedDeltaX: CGFloat = 0
        private let threshold: CGFloat = 36
        private let discreteScrollCooldown: TimeInterval = 0.35
        private var triggeredInCurrentGesture = false
        private var lastDiscreteTrigger = Date.distantPast

        override var acceptsFirstResponder: Bool { false }

        override func scrollWheel(with event: NSEvent) {
            guard isEnabled else { return }

            resetGestureIfNeeded(for: event)
            defer { finishGestureIfNeeded(for: event) }

            guard event.momentumPhase.isEmpty else { return }

            let horizontal = event.scrollingDeltaX
            let vertical = event.scrollingDeltaY
            guard abs(horizontal) > abs(vertical), abs(horizontal) > 0 else {
                return
            }

            guard canTrigger(for: event) else { return }
            accumulatedDeltaX += horizontal
            guard abs(accumulatedDeltaX) >= threshold else { return }

            if accumulatedDeltaX > 0 {
                onNext?()
            } else {
                onPrevious?()
            }
            accumulatedDeltaX = 0
            markTriggered(for: event)
        }

        private func resetGestureIfNeeded(for event: NSEvent) {
            guard event.phase.contains(.mayBegin) || event.phase.contains(.began) else { return }
            accumulatedDeltaX = 0
            triggeredInCurrentGesture = false
        }

        private func finishGestureIfNeeded(for event: NSEvent) {
            guard event.phase.contains(.ended) || event.phase.contains(.cancelled) else { return }
            accumulatedDeltaX = 0
            triggeredInCurrentGesture = false
        }

        private func canTrigger(for event: NSEvent) -> Bool {
            if event.phase.isEmpty {
                return Date().timeIntervalSince(lastDiscreteTrigger) >= discreteScrollCooldown
            }
            return !triggeredInCurrentGesture
        }

        private func markTriggered(for event: NSEvent) {
            if event.phase.isEmpty {
                lastDiscreteTrigger = Date()
            } else {
                triggeredInCurrentGesture = true
            }
        }
    }
}
