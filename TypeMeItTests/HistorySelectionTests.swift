import Foundation
import XCTest
@testable import TypeMeIt

/// Eight rows in the order the history lists them, newest first.
private let rows = (0..<8).map { _ in UUID() }

private func click(_ index: Int, extending: Bool = false, anchor: Int? = nil,
                   selected: [Int] = []) -> Set<Int> {
    let out = HistorySelection.clicked(rows[index], extending: extending,
                                       anchor: anchor.map { rows[$0] }, in: rows,
                                       selected: Set(selected.map { rows[$0] }))
    return Set(out.map { rows.firstIndex(of: $0)! })
}

final class HistorySelectionTests: XCTestCase {
    func testPlainClickTurnsARowOnAndOffAgain() {
        XCTAssertEqual(click(3), [3])
        XCTAssertEqual(click(3, selected: [3]), [])
    }

    func testPlainClickLeavesTheRestOfTheSelectionAlone() {
        XCTAssertEqual(click(5, selected: [1, 2]), [1, 2, 5])
    }

    func testShiftTakesEveryRowDownToTheOneClicked() {
        XCTAssertEqual(click(4, extending: true, anchor: 1, selected: [1]), [1, 2, 3, 4])
    }

    /// The anchor can be below the row clicked; the range is the same either way.
    func testShiftTakesEveryRowUpToTheOneClicked() {
        XCTAssertEqual(click(1, extending: true, anchor: 4, selected: [4]), [1, 2, 3, 4])
    }

    func testShiftKeepsRowsSelectedOutsideTheRange() {
        XCTAssertEqual(click(3, extending: true, anchor: 2, selected: [2, 7]), [2, 3, 7])
    }

    /// Two runs gathered up before deleting: the first survives the second.
    func testASecondRangeAddsToTheFirst() {
        let first = click(2, extending: true, anchor: 0, selected: [0])
        XCTAssertEqual(first, [0, 1, 2])
        XCTAssertEqual(click(6, extending: true, anchor: 5, selected: Array(first)), [0, 1, 2, 5, 6])
    }

    /// Shift never clears: a row already taken by a range stays taken.
    func testShiftDoesNotTurnASelectedRowOff() {
        XCTAssertEqual(click(2, extending: true, anchor: 0, selected: [0, 1, 2]), [0, 1, 2])
    }

    func testShiftOnTheAnchorItselfKeepsIt() {
        XCTAssertEqual(click(3, extending: true, anchor: 3, selected: [3]), [3])
    }

    /// The first box clicked has nothing to measure a range from.
    func testShiftWithNoAnchorIsAPlainClick() {
        XCTAssertEqual(click(3, extending: true, anchor: nil), [3])
    }

    /// The search hid the anchor, or it was deleted. Nothing to measure from,
    /// so the click turns its own row on rather than reaching for a range.
    func testShiftWithAnAnchorThatIsNoLongerListedIsAPlainClick() {
        let gone = UUID()
        let out = HistorySelection.clicked(rows[3], extending: true, anchor: gone, in: rows, selected: [])
        XCTAssertEqual(out, [rows[3]])
    }
}
