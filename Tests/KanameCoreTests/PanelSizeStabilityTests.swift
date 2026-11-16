import XCTest
@testable import KanameCore

/// 面板窗口的高度：收窄列表不得改变窗口大小（否则视觉上就是"跳动"）。
nonisolated final class PanelSizeStabilityTests: XCTestCase {
    private var settings: AppSettingsSnapshot {
        var value = AppSettingsSnapshot()
        value.columnCount = 1
        value.maxItemsPerPage = 24
        return value
    }

    private func state(
        rows: Int, budget: Int, headings: Int = 0, titled: Bool = false, cards: Int = 0
    ) -> PanelState {
        var value = PanelState()
        value.groups = [
            PanelGroup(
                id: "g",
                title: titled ? "System" : "",
                rows: (0..<rows).map { index in
                    PanelRow(
                        id: "r\(index)",
                        keySegments: [],
                        title: "Row \(index)",
                        note: "",
                        isGroup: false,
                        isEnabled: true,
                        hasConflict: false,
                        index: index,
                        isHighlighted: false,
                        isCompleted: false,
                        isFavorite: false,
                        hintLabel: nil
                    )
                }
            )
        ]
        value.rowBudget = budget
        value.headingBudget = headings
        value.cardBudget = cards
        return value
    }

    /// A card with its own id, so two cards in one state are two distinct groups.
    private func group(id: String, title: String, rows: Int) -> PanelGroup {
        PanelGroup(
            id: id,
            title: title,
            rows: (0..<rows).map { index in
                PanelRow(
                    id: "\(id)-r\(index)",
                    keySegments: [],
                    title: "Row \(index)",
                    note: "",
                    isGroup: false,
                    isEnabled: true,
                    hasConflict: false,
                    index: index,
                    isHighlighted: false,
                    isCompleted: false,
                    isFavorite: false,
                    hintLabel: nil
                )
            }
        )
    }

    /// 核心：按下修饰键把 24 行收窄到 3 行，窗口高度必须一动不动。
    func testNarrowingDoesNotResizeThePanel() {
        let wide = state(rows: 24, budget: 24)
        let narrow = state(rows: 3, budget: 24)
        XCTAssertEqual(
            OverlayMetrics.size(for: narrow, settings: settings).height,
            OverlayMetrics.size(for: wide, settings: settings).height
        )
    }

    /// 收窄到极致也不缩：预算是会话内最宽的那份列表。
    func testSingleRowKeepsTheSessionHeight() {
        let one = state(rows: 1, budget: 24)
        let all = state(rows: 24, budget: 24)
        XCTAssertEqual(
            OverlayMetrics.size(for: one, settings: settings).height,
            OverlayMetrics.size(for: all, settings: settings).height
        )
    }

    /// 预算算小了也不能裁掉行：取两者较大值。
    func testFrameStillFitsMoreRowsThanTheBudget() {
        let crowded = state(rows: 30, budget: 4)
        let four = state(rows: 4, budget: 4)
        let size = OverlayMetrics.size(for: crowded, settings: settings)
        XCTAssertGreaterThan(size.height, OverlayMetrics.size(for: four, settings: settings).height)
    }

    /// 预算为 0（还没算出来，比如正在扫描）退回按屏上的行数。
    func testEmptyBudgetFallsBackToTheRowsOnScreen() {
        let withBudget = state(rows: 6, budget: 24)
        let noBudget = state(rows: 6, budget: 0)
        XCTAssertLessThan(
            OverlayMetrics.size(for: noBudget, settings: settings).height,
            OverlayMetrics.size(for: withBudget, settings: settings).height
        )
    }

    /// 标题行同样要预留：最宽列表里的"系统快捷键"标题消失后窗口不能缩。
    func testHeadingBudgetKeepsTheHeadingReserved() {
        let wideWithHeading = state(rows: 24, budget: 24, headings: 1, titled: true)
        var narrowNoHeading = state(rows: 3, budget: 24, headings: 1)
        narrowNoHeading.groups = [
            PanelGroup(id: "g", title: "", rows: narrowNoHeading.groups[0].rows)
        ]
        XCTAssertEqual(
            OverlayMetrics.size(for: narrowNoHeading, settings: settings).height,
            OverlayMetrics.size(for: wideWithHeading, settings: settings).height
        )
    }

    /// 第三条预算：同一会话里第 2 页多一张「系统热键」卡片，窗口不能跟着长高。
    /// 旧公式把 cardChrome 和 gaps 算在当前页的 groups.count 上，翻页就多约 19pt。
    /// 两者还必须落在夹限之内，否则「相等」只是 [190, 720] 夹出来的假象。
    func testASecondCardOnALaterPageDoesNotGrowTheWindow() {
        var pageOne = state(rows: 8, budget: 8, headings: 2, cards: 2)
        pageOne.groups = [group(id: "app", title: "", rows: 8)]
        var pageTwo = state(rows: 8, budget: 8, headings: 2, cards: 2)
        pageTwo.groups = [
            group(id: "app", title: "", rows: 4),
            group(id: "system", title: "System hotkeys", rows: 4)
        ]
        let one = OverlayMetrics.size(for: pageOne, settings: settings)
        let two = OverlayMetrics.size(for: pageTwo, settings: settings)
        XCTAssertGreaterThan(one.height, OverlayMetrics.minPanelHeight)
        XCTAssertLessThan(one.height, OverlayMetrics.maxPanelHeight)
        XCTAssertEqual(one.height, two.height)
    }

    /// 收窄到一行时，卡片预算同样要兜住 cardChrome 与 gaps。
    func testNarrowingKeepsTheCardBudgetReserved() {
        var wide = state(rows: 8, budget: 8, headings: 2, cards: 2)
        wide.groups = [
            group(id: "app", title: "", rows: 4),
            group(id: "system", title: "System hotkeys", rows: 4)
        ]
        var narrow = wide
        narrow.groups = [group(id: "app", title: "", rows: 1)]
        XCTAssertEqual(
            OverlayMetrics.size(for: narrow, settings: settings).height,
            OverlayMetrics.size(for: wide, settings: settings).height
        )
    }

    /// cardBudget 还没算出来（0）时退回当前页的卡片数，旧行为保持不变。
    func testZeroCardBudgetFallsBackToTheCardsOnScreen() {
        var one = state(rows: 8, budget: 8, headings: 2)
        one.groups = [group(id: "app", title: "", rows: 8)]
        var two = state(rows: 8, budget: 8, headings: 2)
        two.groups = [
            group(id: "app", title: "", rows: 4),
            group(id: "system", title: "System hotkeys", rows: 4)
        ]
        XCTAssertGreaterThan(
            OverlayMetrics.size(for: two, settings: settings).height,
            OverlayMetrics.size(for: one, settings: settings).height
        )
    }

    /// 高度始终夹在 [190, 720]。
    func testHeightIsClamped() {
        XCTAssertEqual(OverlayMetrics.size(for: state(rows: 1, budget: 0), settings: settings).height, 190)
        XCTAssertEqual(OverlayMetrics.size(for: state(rows: 24, budget: 24), settings: settings).height, 720)
    }
}
