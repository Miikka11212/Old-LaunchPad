import Foundation
import CoreGraphics

struct LaunchpadGrid {
    let width: CGFloat
    let height: CGFloat
    let columns: Int
    let rows: Int
    let tileWidth: CGFloat = 140
    let tileHeight: CGFloat = 112
    var pageSize: Int { columns * rows }

    init(width: CGFloat, height: CGFloat) {
        self.width = max(0, width)
        self.height = max(0, height)
        columns = max(1, min(7, Int(max(0, width) / 104)))
        rows = max(1, min(5, Int(max(0, height) / 100)))
    }

    func pageCount(for count: Int) -> Int { (max(0, count) + pageSize - 1) / pageSize }

    func range(for page: Int, count: Int) -> Range<Int> {
        let start = min(max(0, count), max(0, page) * pageSize)
        return start..<min(max(0, count), start + pageSize)
    }

    func frame(at index: Int) -> CGRect {
        let cellWidth = width / CGFloat(columns)
        let cellHeight = height / CGFloat(rows)
        let itemWidth = min(tileWidth, cellWidth)
        let itemHeight = min(tileHeight, cellHeight)
        let x: CGFloat = CGFloat(index % columns) * cellWidth + (cellWidth - itemWidth) / 2
        let y: CGFloat = CGFloat(index / columns) * cellHeight + (cellHeight - itemHeight) / 2
        return CGRect(x: x, y: y, width: itemWidth, height: itemHeight)
    }

    func movedIndex(from index: Int, by offset: Int, count: Int) -> Int? {
        guard count > 0 else { return nil }
        return min(count - 1, max(0, index + offset))
    }
}

/// Momentum never turns a second page. Phase-less mouse wheels reset after a pause.
struct PageScrollAccumulator {
    private var total: CGFloat = 0
    private var changed = false
    private var lastTimestamp: TimeInterval = -.infinity

    mutating func consume(deltaX: CGFloat, deltaY: CGFloat, began: Bool, ended: Bool,
                          isMomentum: Bool, isDiscrete: Bool, timestamp: TimeInterval) -> CGFloat? {
        guard !isMomentum else { return nil }
        if began || (isDiscrete && timestamp - lastTimestamp > 0.3) {
            total = 0
            changed = false
        }
        lastTimestamp = timestamp
        defer {
            if ended { total = 0; changed = false }
        }
        guard abs(deltaX) > abs(deltaY), !changed else { return nil }
        total += deltaX
        guard abs(total) >= 40 else { return nil }
        changed = true
        return total
    }
}
