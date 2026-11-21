import XCTest
@testable import ClaudeUsageBar

final class MenuBarIconRendererTests: XCTestCase {
    private func icon(_ pct7d: Double, percentages: Bool = true, colors: Bool = false) -> NSImage {
        renderIcon(pct5h: 0.42, pct7d: pct7d, showsPercentages: percentages, usesWarningColors: colors)
    }

    func testPercentagesWidenTheIconOnlyAt100Percent() {
        XCTAssertGreaterThan(icon(0.87).size.width, icon(0.87, percentages: false).size.width)
        XCTAssertEqual(icon(0.05).size.width, icon(0.99).size.width)
        XCTAssertGreaterThan(icon(1.0).size.width, icon(0.99).size.width)
    }

    func testWarningColorsStartAt60Percent() {
        XCTAssertTrue(icon(0.59, colors: true).isTemplate)
        XCTAssertFalse(icon(0.60, colors: true).isTemplate)
        XCTAssertTrue(icon(0.95, colors: false).isTemplate)
    }
}
