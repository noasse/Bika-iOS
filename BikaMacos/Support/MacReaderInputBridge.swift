import AppKit
import SwiftUI

/// Page-level actions the reader window can be driven with from the keyboard.
nonisolated enum MacReaderKeyCommand: Equatable {
    case previousPage
    case nextPage
    case firstPage
    case lastPage
}

nonisolated enum MacReaderKeyMapping {
    enum KeyCode {
        static let space: UInt16 = 49
        static let leftArrow: UInt16 = 123
        static let rightArrow: UInt16 = 124
        static let downArrow: UInt16 = 125
        static let upArrow: UInt16 = 126
        static let pageUp: UInt16 = 116
        static let pageDown: UInt16 = 121
        static let home: UInt16 = 115
        static let end: UInt16 = 119
    }

    static func command(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags
    ) -> MacReaderKeyCommand? {
        // Modifier chords belong to the menu bar, except Shift+Space for paging back.
        let relevantModifiers = modifiers.intersection(.deviceIndependentFlagsMask)
        let isShiftOnly = relevantModifiers == .shift
        guard relevantModifiers.isEmpty || isShiftOnly else { return nil }

        switch keyCode {
        case KeyCode.space:
            return isShiftOnly ? .previousPage : .nextPage
        case KeyCode.leftArrow, KeyCode.upArrow, KeyCode.pageUp:
            return .previousPage
        case KeyCode.rightArrow, KeyCode.downArrow, KeyCode.pageDown:
            return .nextPage
        case KeyCode.home:
            return .firstPage
        case KeyCode.end:
            return .lastPage
        default:
            return nil
        }
    }
}

struct MacReaderKeyboardBridge: NSViewRepresentable {
    var isEnabled = true
    let onCommand: (MacReaderKeyCommand) -> Void

    func makeNSView(context: Context) -> KeyView {
        let view = KeyView()
        view.isEnabled = isEnabled
        view.onCommand = onCommand
        return view
    }

    func updateNSView(_ nsView: KeyView, context: Context) {
        nsView.isEnabled = isEnabled
        nsView.onCommand = onCommand
        guard isEnabled else { return }
        nsView.claimFirstResponderIfUnclaimed()
    }

    final class KeyView: NSView {
        var isEnabled = true
        var onCommand: ((MacReaderKeyCommand) -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            claimFirstResponderIfUnclaimed()
        }

        /// Claims keyboard focus only when it is actually needed. `updateNSView` runs on every
        /// SwiftUI state change, so re-claiming unconditionally churned the responder chain on
        /// every page turn and tore down any active field editor.
        func claimFirstResponderIfUnclaimed() {
            guard isEnabled, let window else { return }
            guard shouldClaimFirstResponder(from: window.firstResponder) else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isEnabled, let window = self.window else { return }
                guard self.shouldClaimFirstResponder(from: window.firstResponder) else { return }
                window.makeFirstResponder(self)
            }
        }

        private func shouldClaimFirstResponder(from responder: NSResponder?) -> Bool {
            guard responder !== self else { return false }
            if let text = responder as? NSText, text.isFieldEditor { return false }
            if responder is NSTextView { return false }
            return true
        }

        override func keyDown(with event: NSEvent) {
            guard
                isEnabled,
                let command = MacReaderKeyMapping.command(
                    keyCode: event.keyCode,
                    modifiers: event.modifierFlags
                )
            else {
                super.keyDown(with: event)
                return
            }

            onCommand?(command)
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
