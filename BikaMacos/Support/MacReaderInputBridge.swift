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

nonisolated enum MacReaderSwipeDirection: Equatable {
    case previous
    case next
}

/// Turns a stream of horizontal scroll deltas into discrete page turns.
///
/// Trackpad gestures carry phase information and must only fire once per swipe; a mouse wheel
/// reports no phase at all, so those fall back to a cooldown.
nonisolated struct MacHorizontalSwipeAccumulator {
    struct Event {
        var deltaX: CGFloat
        var deltaY: CGFloat
        var phase: NSEvent.Phase
        var momentumPhase: NSEvent.Phase
        var timestamp: TimeInterval
    }

    var threshold: CGFloat = 36
    var discreteScrollCooldown: TimeInterval = 0.35

    private var accumulatedDeltaX: CGFloat = 0
    private var triggeredInCurrentGesture = false
    private var lastDiscreteTrigger: TimeInterval = -.greatestFiniteMagnitude

    mutating func reset() {
        accumulatedDeltaX = 0
        triggeredInCurrentGesture = false
    }

    mutating func consume(_ event: Event) -> MacReaderSwipeDirection? {
        if event.phase.contains(.mayBegin) || event.phase.contains(.began) {
            accumulatedDeltaX = 0
            triggeredInCurrentGesture = false
        }
        defer {
            if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
                accumulatedDeltaX = 0
                triggeredInCurrentGesture = false
            }
        }

        guard event.momentumPhase.isEmpty else { return nil }
        guard abs(event.deltaX) > abs(event.deltaY), abs(event.deltaX) > 0 else { return nil }
        guard canTrigger(event) else { return nil }

        accumulatedDeltaX += event.deltaX
        guard abs(accumulatedDeltaX) >= threshold else { return nil }

        let direction: MacReaderSwipeDirection = accumulatedDeltaX > 0 ? .next : .previous
        accumulatedDeltaX = 0
        markTriggered(event)
        return direction
    }

    /// True when the gesture is horizontal enough that the reader, not the scroll view, owns it.
    static func isHorizontalDominant(deltaX: CGFloat, deltaY: CGFloat) -> Bool {
        abs(deltaX) > abs(deltaY) && abs(deltaX) > 0
    }

    private func canTrigger(_ event: Event) -> Bool {
        if event.phase.isEmpty {
            return event.timestamp - lastDiscreteTrigger >= discreteScrollCooldown
        }
        return !triggeredInCurrentGesture
    }

    private mutating func markTriggered(_ event: Event) {
        if event.phase.isEmpty {
            lastDiscreteTrigger = event.timestamp
        } else {
            triggeredInCurrentGesture = true
        }
    }
}
