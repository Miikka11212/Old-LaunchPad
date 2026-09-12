import AppKit

let launcherItemPasteboardType = NSPasteboard.PasteboardType("local.oldlaunchpad.item")

final class OrganizationViewport: PagingViewportView {
    var updateDrop: ((NSDraggingInfo) -> NSDragOperation)?
    var acceptDrop: ((NSDraggingInfo) -> Bool)?
    var exitDrop: (() -> Void)?
    var backgroundMenu: (() -> NSMenu)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([launcherItemPasteboardType])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func menu(for event: NSEvent) -> NSMenu? { backgroundMenu?() }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { updateDrop?(sender) ?? [] }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { updateDrop?(sender) ?? [] }
    override func draggingExited(_ sender: NSDraggingInfo?) { exitDrop?() }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { sender.draggingSource is AppTileButton }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool { acceptDrop?(sender) ?? false }
    override func concludeDragOperation(_ sender: NSDraggingInfo?) { exitDrop?() }
    override func wantsPeriodicDraggingUpdates() -> Bool { true }
}

final class FolderBackButton: NSButton {
    var moveOut: ((String) -> Bool)?
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([launcherItemPasteboardType])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingSource is AppTileButton ? .move : []
    }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { sender.draggingSource is AppTileButton }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard sender.draggingSource is AppTileButton,
              let id = sender.draggingPasteboard.string(forType: launcherItemPasteboardType) else { return false }
        return moveOut?(id) ?? false
    }
}

final class AppTileButton: NSButton, NSDraggingSource {
    override var isFlipped: Bool { false }
    let itemID: String
    let launchpadApp: LaunchpadApp?
    let displayIcon: NSImage
    var keyboardSelected = false { didSet { needsDisplay = true } }
    var dropHighlighted = false { didSet { needsDisplay = true } }
    var contextualMenu: (() -> NSMenu)?
    var dragStarted: (() -> Void)?
    var dragEnded: (() -> Void)?
    var canDrag = true

    init(id: String, name: String, icon: NSImage, app: LaunchpadApp? = nil) {
        itemID = id
        launchpadApp = app
        displayIcon = icon
        super.init(frame: .zero)
        title = name
        toolTip = name
        isBordered = false
        setButtonType(.momentaryPushIn)
        setAccessibilityLabel(name)
        setAccessibilityHelp("Open \(name). Drag to rearrange; right-click for more actions.")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func menu(for event: NSEvent) -> NSMenu? { contextualMenu?() }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control), let menu = contextualMenu?() {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
            return
        }
        guard canDrag, let window else { super.mouseDown(with: event); return }
        let start = convert(event.locationInWindow, from: nil)
        highlight(true)
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp], until: .distantFuture, inMode: .eventTracking, dequeue: true) {
            let point = convert(next.locationInWindow, from: nil)
            if next.type == .leftMouseUp {
                highlight(false)
                if bounds.contains(point) { _ = sendAction(action, to: target) }
                return
            }
            if hypot(point.x - start.x, point.y - start.y) >= 5 {
                highlight(false)
                let item = NSPasteboardItem()
                item.setString(itemID, forType: launcherItemPasteboardType)
                let drag = NSDraggingItem(pasteboardWriter: item)
                let preview = NSImage(size: bounds.size)
                preview.lockFocus()
                draw(bounds)
                preview.unlockFocus()
                drag.setDraggingFrame(bounds, contents: preview)
                dragStarted?()
                alphaValue = 0.35
                let session = beginDraggingSession(with: [drag], event: next, source: self)
                session.animatesToStartingPositionsOnCancelOrFail = true
                return
            }
        }
        highlight(false)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        alphaValue = 1
        dragEnded?()
    }

    override func draw(_ dirtyRect: NSRect) {
        let background = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 16, yRadius: 16)
        if isHighlighted || keyboardSelected || dropHighlighted {
            NSColor.white.withAlphaComponent(dropHighlighted ? 0.24 : isHighlighted ? 0.23 : 0.11).setFill()
            background.fill()
        }
        if keyboardSelected || dropHighlighted {
            NSColor.white.withAlphaComponent(0.75).setStroke()
            background.lineWidth = 2
            background.stroke()
        }
        let iconSize = max(0, min(88, bounds.width - 24, bounds.height - 40))
        let labelY = max(4, (bounds.height - iconSize - 26) / 2)
        displayIcon.draw(in: NSRect(x: (bounds.width - iconSize) / 2, y: labelY + 24, width: iconSize, height: iconSize), from: .zero, operation: .sourceOver, fraction: isHighlighted ? 0.75 : 1)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        (title as NSString).draw(in: NSRect(x: 3, y: labelY, width: bounds.width - 6, height: 18), withAttributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph
        ])
    }
}

@MainActor
func folderImage(icons: [NSImage]) -> NSImage {
    let image = NSImage(size: NSSize(width: 128, height: 128))
    image.lockFocus()
    NSColor(white: 0.80, alpha: 0.55).setFill()
    NSBezierPath(roundedRect: NSRect(x: 4, y: 4, width: 120, height: 120), xRadius: 26, yRadius: 26).fill()
    NSColor.white.withAlphaComponent(0.35).setStroke()
    NSBezierPath(roundedRect: NSRect(x: 4.5, y: 4.5, width: 119, height: 119), xRadius: 26, yRadius: 26).stroke()
    for (index, icon) in icons.prefix(9).enumerated() {
        let rect = NSRect(x: 16 + (index % 3) * 33, y: 83 - (index / 3) * 33, width: 28, height: 28)
        icon.draw(in: rect)
    }
    image.unlockFocus()
    return image
}
