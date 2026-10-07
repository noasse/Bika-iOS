import AppKit
import XCTest
@testable import BikaMacos

final class MacReaderInputTests: XCTestCase {
    private typealias KeyCode = MacReaderKeyMapping.KeyCode

    func testUnmodifiedKeysMapToPageNavigation() {
        XCTAssertEqual(command(KeyCode.rightArrow), .nextPage)
        XCTAssertEqual(command(KeyCode.downArrow), .nextPage)
        XCTAssertEqual(command(KeyCode.pageDown), .nextPage)
        XCTAssertEqual(command(KeyCode.space), .nextPage)

        XCTAssertEqual(command(KeyCode.leftArrow), .previousPage)
        XCTAssertEqual(command(KeyCode.upArrow), .previousPage)
        XCTAssertEqual(command(KeyCode.pageUp), .previousPage)

        XCTAssertEqual(command(KeyCode.home), .firstPage)
        XCTAssertEqual(command(KeyCode.end), .lastPage)
    }

    func testShiftSpacePagesBackwardsWhileOtherChordsFallThrough() {
        XCTAssertEqual(command(KeyCode.space, modifiers: .shift), .previousPage)
        XCTAssertEqual(command(KeyCode.rightArrow, modifiers: .shift), .nextPage)

        // Chords belong to the menu bar, so the reader must not swallow them.
        XCTAssertNil(command(KeyCode.rightArrow, modifiers: .command))
        XCTAssertNil(command(KeyCode.space, modifiers: [.command, .shift]))
        XCTAssertNil(command(KeyCode.leftArrow, modifiers: .option))
    }

    func testUnrelatedKeysAreNotConsumed() {
        XCTAssertNil(command(0))
        XCTAssertNil(command(53)) // Escape must stay available to the system.
    }

    // MARK: - Horizontal swipe

    func testTrackpadGestureTurnsOnePageEvenWhenItKeepsScrolling() {
        var accumulator = MacHorizontalSwipeAccumulator()

        XCTAssertNil(accumulator.consume(event(deltaX: 0, phase: .began)))
        XCTAssertNil(accumulator.consume(event(deltaX: 20)))
        XCTAssertEqual(accumulator.consume(event(deltaX: 20)), .next)

        // One page per gesture: the rest of the swipe must not keep paging.
        XCTAssertNil(accumulator.consume(event(deltaX: 40)))
        XCTAssertNil(accumulator.consume(event(deltaX: 40)))

        XCTAssertNil(accumulator.consume(event(deltaX: 0, phase: .ended)))
        XCTAssertNil(accumulator.consume(event(deltaX: 0, phase: .began)))
        XCTAssertEqual(accumulator.consume(event(deltaX: -40)), .previous)
    }

    func testMomentumAndVerticalScrollNeverTurnPages() {
        var accumulator = MacHorizontalSwipeAccumulator()

        XCTAssertNil(
            accumulator.consume(event(deltaX: 80, phase: .changed, momentumPhase: .changed))
        )
        XCTAssertNil(accumulator.consume(event(deltaX: 4, deltaY: 60)))
        XCTAssertNil(accumulator.consume(event(deltaX: 0, deltaY: 60)))
    }

    func testMouseWheelPagingIsRateLimitedByTheCooldown() {
        var accumulator = MacHorizontalSwipeAccumulator()

        // A wheel reports no phase at all, so the cooldown is what stops a runaway page flip.
        XCTAssertEqual(accumulator.consume(event(deltaX: 40, phase: [], timestamp: 100)), .next)
        XCTAssertNil(accumulator.consume(event(deltaX: 40, phase: [], timestamp: 100.1)))
        XCTAssertEqual(accumulator.consume(event(deltaX: 40, phase: [], timestamp: 100.5)), .next)
    }

    func testHorizontalDominanceGatesWhoOwnsTheGesture() {
        XCTAssertTrue(MacHorizontalSwipeAccumulator.isHorizontalDominant(deltaX: 10, deltaY: 2))
        XCTAssertFalse(MacHorizontalSwipeAccumulator.isHorizontalDominant(deltaX: 2, deltaY: 10))
        XCTAssertFalse(MacHorizontalSwipeAccumulator.isHorizontalDominant(deltaX: 0, deltaY: 0))
    }

    // MARK: - Helpers

    private func event(
        deltaX: CGFloat,
        deltaY: CGFloat = 0,
        phase: NSEvent.Phase = .changed,
        momentumPhase: NSEvent.Phase = [],
        timestamp: TimeInterval = 0
    ) -> MacHorizontalSwipeAccumulator.Event {
        MacHorizontalSwipeAccumulator.Event(
            deltaX: deltaX,
            deltaY: deltaY,
            phase: phase,
            momentumPhase: momentumPhase,
            timestamp: timestamp
        )
    }

    private func command(
        _ keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags = []
    ) -> MacReaderKeyCommand? {
        MacReaderKeyMapping.command(keyCode: keyCode, modifiers: modifiers)
    }
}
