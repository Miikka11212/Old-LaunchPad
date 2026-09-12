import Foundation
import CoreGraphics

struct NavigationTests {
    func testClassicGridAndResponsiveBounds() {
        let desktop = LaunchpadGrid(width: 1050, height: 750)
        assert(desktop.columns == 7)
        assert(desktop.rows == 5)
        for (width, height) in [(1050.0, 650.0), (896, 520), (700, 400), (280, 220), (80, 70), (0, 0)] {
            let grid = LaunchpadGrid(width: width, height: height)
            assert(grid.pageSize > 0)
            for index in 0..<grid.pageSize {
                let frame = grid.frame(at: index)
                assert(frame.minX >= 0)
                assert(frame.minY >= 0)
                assert(frame.maxX <= width + 0.001)
                assert(frame.maxY <= height + 0.001)
            }
        }
    }

    func testCompactFolderAndHitTargets() {
        let folder = LaunchpadGrid(width: 464, height: 428, isFolder: true)
        assert(folder.columns == 3 && folder.rows == 3 && folder.pageSize == 9)
        assert(folder.pageCount(for: 10) == 2)
        assert(folder.range(for: 1, count: 10) == 9..<10)
        let small = LaunchpadGrid(width: 300, height: 280, isFolder: true)
        assert(small.columns <= 3 && small.rows <= 3)
        let target = TileGeometry(size: CGSize(width: 150, height: 136), labelWidth: 42)
        assert(target.contains(CGPoint(x: target.icon.midX, y: target.icon.midY)))
        assert(target.contains(CGPoint(x: target.label.midX, y: target.label.midY)))
        assert(!target.contains(CGPoint(x: 5, y: 65)))
        assert(!target.contains(CGPoint(x: 75, y: 132)))
        assert(!target.contains(CGPoint(x: 5, y: target.label.midY)))
        assert(!target.contains(CGPoint(x: 75, y: target.label.maxY + 2)))
        print("Passed compact folder pagination and tight icon hit-target checks.")
    }

    func testPageBoundariesAndEmptyResults() {
        let grid = LaunchpadGrid(width: 1050, height: 750)
        assert(grid.pageCount(for: 0) == 0)
        assert(grid.pageCount(for: 35) == 1)
        assert(grid.pageCount(for: 36) == 2)
        assert(grid.range(for: 1, count: 36) == 35..<36)
        assert(grid.range(for: 4, count: 36) == 36..<36)
        assert(grid.range(for: 0, count: 0) == 0..<0)
    }

    func testKeyboardNavigationAcrossPagesAndPartialRows() {
        let grid = LaunchpadGrid(width: 1050, height: 750)
        assert(grid.movedIndex(from: 0, by: 1, count: 0) == nil)
        assert(grid.movedIndex(from: 0, by: -1, count: 38) == 0)
        assert(grid.movedIndex(from: 34, by: 1, count: 38) == 35)
        assert(grid.movedIndex(from: 32, by: 7, count: 38) == 37)
        assert(grid.movedIndex(from: 37, by: 1, count: 38) == 37)
    }

    func testGestureTurnsOnlyOnePageAndIgnoresMomentum() {
        var scroll = PageScrollAccumulator()
        assert(scroll.consume(deltaX: -20, deltaY: 0, began: true, ended: false, isMomentum: false, isDiscrete: false, timestamp: 1) == nil)
        assert(scroll.consume(deltaX: -25, deltaY: 0, began: false, ended: false, isMomentum: false, isDiscrete: false, timestamp: 1.1) == -45)
        assert(scroll.consume(deltaX: -80, deltaY: 0, began: false, ended: false, isMomentum: false, isDiscrete: false, timestamp: 1.2) == nil)
        assert(scroll.consume(deltaX: 0, deltaY: 0, began: false, ended: true, isMomentum: false, isDiscrete: false, timestamp: 1.3) == nil)
        assert(scroll.consume(deltaX: -80, deltaY: 0, began: false, ended: false, isMomentum: true, isDiscrete: false, timestamp: 1.4) == nil)
        assert(scroll.consume(deltaX: 50, deltaY: 0, began: true, ended: false, isMomentum: false, isDiscrete: false, timestamp: 2) == 50)
    }

    func testMouseWheelResetsAfterPauseAndVerticalMovementDoesNotPage() {
        var scroll = PageScrollAccumulator()
        assert(scroll.consume(deltaX: 50, deltaY: 100, began: true, ended: false, isMomentum: false, isDiscrete: false, timestamp: 1) == nil)
        assert(scroll.consume(deltaX: 45, deltaY: 0, began: false, ended: false, isMomentum: false, isDiscrete: true, timestamp: 2) == 45)
        assert(scroll.consume(deltaX: 45, deltaY: 0, began: false, ended: false, isMomentum: false, isDiscrete: true, timestamp: 2.1) == nil)
        assert(scroll.consume(deltaX: 45, deltaY: 0, began: false, ended: false, isMomentum: false, isDiscrete: true, timestamp: 3) == 45)
    }
}

@main
struct NavigationChecks {
    @MainActor static func main() throws {
        try checkLauncherLayout()
        checkAppVisibility()
        let tests = NavigationTests()
        tests.testCompactFolderAndHitTargets()
        tests.testClassicGridAndResponsiveBounds()
        tests.testPageBoundariesAndEmptyResults()
        tests.testKeyboardNavigationAcrossPagesAndPartialRows()
        tests.testGestureTurnsOnlyOnePageAndIgnoresMomentum()
        tests.testMouseWheelResetsAfterPauseAndVerticalMovementDoesNotPage()
        print("Passed all 5 navigation checks (including grid bounds at 6 viewport sizes).")
    }
}
