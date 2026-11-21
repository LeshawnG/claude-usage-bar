import XCTest
@testable import ClaudeUsageBar

final class MenuBarIconRendererTests: XCTestCase {
    private func icon(_ pct7d: Double, percentages: Bool = true) -> NSImage {
        renderIcon(pct5h: 0.42, pct7d: pct7d, showsPercentages: percentages)
    }

    func testPercentagesWidenTheIconOnlyAt100Percent() {
        XCTAssertGreaterThan(icon(0.87).size.width, icon(0.87, percentages: false).size.width)
        XCTAssertEqual(icon(0.05).size.width, icon(0.99).size.width)
        XCTAssertGreaterThan(icon(1.0).size.width, icon(0.99).size.width)
    }
}
