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

    private func command(
        _ keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags = []
    ) -> MacReaderKeyCommand? {
        MacReaderKeyMapping.command(keyCode: keyCode, modifiers: modifiers)
    }
}
