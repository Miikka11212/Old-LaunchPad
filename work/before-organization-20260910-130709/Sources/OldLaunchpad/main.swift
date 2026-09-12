import AppKit
import Carbon
import CoreImage

struct LaunchpadApp: Identifiable, Hashable {
    let id: String
    let name: String
    let path: String
    let category: String
    let icon: NSImage
}

@MainActor
final class AppCatalog: ObservableObject {
    @Published var apps: [LaunchpadApp] = []

    let categories = [
        "All",
        "Social",
        "Utilities",
        "Entertainment",
        "Productivity & Finance",
        "Information & Reading",
        "Creativity",
        "Other"
    ]

    func reload() {
        let roots = [
            "/Applications",
            NSHomeDirectory() + "/Applications",
            "/System/Applications",
            "/System/Applications/Utilities"
        ]

        var seen = Set<String>()
        var loaded: [LaunchpadApp] = []

        for root in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: URL(fileURLWithPath: root),
                includingPropertiesForKeys: [.isApplicationKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                continue
            }

            for case let url as URL in enumerator {
                guard url.pathExtension == "app", !seen.contains(url.path) else {
                    continue
                }

                seen.insert(url.path)
                if let app = makeApp(from: url) { loaded.append(app) }
            }
        }

        // Some system apps live outside the enumerated roots (or are symlinked).
        for identifier in ["com.apple.Safari", "com.apple.finder"] {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier),
               !loaded.contains(where: { URL(fileURLWithPath: $0.path).resolvingSymlinksInPath() == url.resolvingSymlinksInPath() }) {
                if let app = makeApp(from: url) { loaded.append(app) }
            }
        }

        apps = loaded.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func makeApp(from url: URL) -> LaunchpadApp? {
        let infoURL = url.appendingPathComponent("Contents/Info.plist")
        let info = (try? Data(contentsOf: infoURL)).flatMap {
            try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any]
        }
        guard !AppVisibility.isHidden(
            bundleIdentifier: info?["CFBundleIdentifier"] as? String ?? "",
            path: url.resolvingSymlinksInPath().path,
            isAgent: (info?["LSUIElement"] as? NSNumber)?.boolValue ?? false,
            isBackgroundOnly: (info?["LSBackgroundOnly"] as? NSNumber)?.boolValue ?? false
        ) else { return nil }
        let bundleName = info?["CFBundleDisplayName"] as? String
            ?? info?["CFBundleName"] as? String
            ?? url.deletingPathExtension().lastPathComponent
        let rawCategory = info?["LSApplicationCategoryType"] as? String
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 128, height: 128)

        return LaunchpadApp(
            id: url.path,
            name: bundleName,
            path: url.path,
            category: normalizeCategory(rawCategory),
            icon: icon
        )
    }

    private func normalizeCategory(_ raw: String?) -> String {
        guard let raw else { return "Other" }

        if raw.contains("social") { return "Social" }
        if raw.contains("utilities") || raw.contains("developer-tools") { return "Utilities" }
        if raw.contains("games") || raw.contains("music") || raw.contains("video") || raw.contains("entertainment") {
            return "Entertainment"
        }
        if raw.contains("finance") || raw.contains("business") || raw.contains("productivity") {
            return "Productivity & Finance"
        }
        if raw.contains("books") || raw.contains("news") || raw.contains("reference") || raw.contains("education") {
            return "Information & Reading"
        }
        if raw.contains("graphics-design") || raw.contains("photography") || raw.contains("design") {
            return "Creativity"
        }

        return "Other"
    }
}

final class OverlayWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class LaunchpadController {
    private let catalog = AppCatalog()
    private var window: OverlayWindow?
    private var keyMonitor: Any?
    private var isClosing = false
    private var visibilityGeneration = 0

    func toggle() {
        if window?.isVisible == true && !isClosing {
            hide()
        } else {
            show()
        }
    }

    func show() {
        guard window?.isVisible != true else {
            if isClosing { animateVisibility(visible: true) }
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
            return
        }

        catalog.reload()

        let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        let screenFrame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let panel = OverlayWindow(
            contentRect: screenFrame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.alphaValue = 0
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.contentViewController = LaunchpadViewController(
            catalog: catalog,
            topInset: max(24, screen?.safeAreaInsets.top ?? 0,
                          screen.map { $0.frame.maxY - $0.visibleFrame.maxY } ?? 0) + 20
        ) { [weak self] in
            self?.hide()
        }
        panel.minSize = screenFrame.size
        panel.maxSize = screenFrame.size
        panel.setFrame(screenFrame, display: false)

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, window.isVisible,
                  event.window == nil || event.window === window else { return event }
            if self.isClosing { return nil }
            if event.keyCode == 53 {
                self.hide()
                return nil
            }
            let controller = window.contentViewController as? LaunchpadViewController
            return controller?.handleKey(event) == true ? nil : event
        }

        window = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        animateVisibility(visible: true, initial: true)
    }

    func hide() {
        guard window != nil, !isClosing else { return }
        animateVisibility(visible: false)
    }

    private func animateVisibility(visible: Bool, initial: Bool = false) {
        guard let panel = window else { return }
        visibilityGeneration += 1
        let generation = visibilityGeneration
        isClosing = !visible
        panel.ignoresMouseEvents = !visible
        let reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let duration = reducedMotion ? 0.14 : (visible ? 0.34 : 0.26)
        (panel.contentViewController as? LaunchpadViewController)?.animatePresentation(
            visible: visible, initial: initial, duration: duration, reducedMotion: reducedMotion
        )
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.75, 0.25, 1)
            panel.animator().alphaValue = visible ? 1 : 0
        } completionHandler: { [weak self, weak panel] in
            Task { @MainActor in
                guard let self, let panel, self.window === panel,
                      self.visibilityGeneration == generation, !visible else { return }
                self.finishHiding(panel)
            }
        }
    }

    private func finishHiding(_ panel: OverlayWindow) {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }

        panel.orderOut(nil)
        window = nil
        isClosing = false
    }
}

final class LaunchpadViewController: NSViewController, NSSearchFieldDelegate {
    private let catalog: AppCatalog
    private let dismiss: () -> Void
    private let topInset: CGFloat
    private let searchField = NSSearchField()
    private let searchBackground = NSView()
    private let pageViewport = PagingViewportView()
    private var pageDocument = FlippedView()
    private let wallpaper = WallpaperView()
    private var isChangingPage = false
    private var queuedPage: Int?
    private var pageGeneration = 0
    private let pageDots = NSStackView()
    private let emptyState = NSTextField(wrappingLabelWithString: "")
    private var apps: [LaunchpadApp] = []
    private var selectedIndex: Int?
    private var currentPage = 0
    private var grid = LaunchpadGrid(width: 1, height: 1)
    private var lastViewportSize = NSSize.zero
    private var tiles: [Int: AppTileButton] = [:]
    private var pageCount: Int { grid.pageCount(for: apps.count) }

    init(catalog: AppCatalog, topInset: CGFloat, dismiss: @escaping () -> Void) {
        self.catalog = catalog
        self.topInset = topInset
        self.dismiss = dismiss
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.appearance = NSAppearance(named: .darkAqua)

        wallpaper.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(wallpaper)
        pin(wallpaper, to: view)

        configureSearchField()
        searchBackground.translatesAutoresizingMaskIntoConstraints = false
        searchBackground.wantsLayer = true
        searchBackground.layer?.cornerRadius = 10
        searchBackground.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.24).cgColor
        searchBackground.layer?.borderWidth = 0.5
        searchBackground.layer?.borderColor = NSColor.white.withAlphaComponent(0.30).cgColor
        view.addSubview(searchBackground)
        searchBackground.addSubview(searchField)
        let searchIcon = NSImageView(image: NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)!)
        searchIcon.contentTintColor = .white.withAlphaComponent(0.65)
        searchIcon.translatesAutoresizingMaskIntoConstraints = false
        searchBackground.addSubview(searchIcon)

        configurePages()
        view.addSubview(pageViewport)
        view.addSubview(emptyState)
        view.addSubview(pageDots)
        NSLayoutConstraint.activate([
            searchBackground.topAnchor.constraint(equalTo: view.topAnchor, constant: topInset),
            searchBackground.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            searchBackground.widthAnchor.constraint(equalToConstant: 280),
            searchBackground.heightAnchor.constraint(equalToConstant: 38),
            searchField.centerYAnchor.constraint(equalTo: searchBackground.centerYAnchor),
            searchField.leadingAnchor.constraint(equalTo: searchBackground.leadingAnchor, constant: 36),
            searchField.trailingAnchor.constraint(equalTo: searchBackground.trailingAnchor, constant: -10),
            searchField.heightAnchor.constraint(equalToConstant: 24),
            searchIcon.leadingAnchor.constraint(equalTo: searchBackground.leadingAnchor, constant: 12),
            searchIcon.centerYAnchor.constraint(equalTo: searchBackground.centerYAnchor),
            searchIcon.widthAnchor.constraint(equalToConstant: 14),
            searchIcon.heightAnchor.constraint(equalToConstant: 14),
            pageViewport.topAnchor.constraint(equalTo: searchBackground.bottomAnchor, constant: 28),
            pageViewport.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pageViewport.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.78),
            pageViewport.bottomAnchor.constraint(equalTo: pageDots.topAnchor, constant: -16),
            pageDots.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pageDots.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -82),
            pageDots.heightAnchor.constraint(equalToConstant: 18),
            emptyState.centerXAnchor.constraint(equalTo: pageViewport.centerXAnchor),
            emptyState.centerYAnchor.constraint(equalTo: pageViewport.centerYAnchor),
            emptyState.widthAnchor.constraint(lessThanOrEqualTo: pageViewport.widthAnchor, constant: -40)
        ])
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        rebuildPages()
        view.window?.makeFirstResponder(searchField)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        guard pageViewport.bounds.size != lastViewportSize else { return }
        lastViewportSize = pageViewport.bounds.size
        let anchorIndex = selectedIndex ?? currentPage * grid.pageSize
        grid = LaunchpadGrid(width: lastViewportSize.width, height: lastViewportSize.height)
        currentPage = min(anchorIndex / grid.pageSize, max(0, pageCount - 1))
        layoutPages()
    }

    func controlTextDidChange(_ notification: Notification) { rebuildPages() }

    private func configureSearchField() {
        searchField.font = .systemFont(ofSize: 15)
        searchField.textColor = .white.withAlphaComponent(0.95)
        searchField.drawsBackground = false
        searchField.isBordered = false
        (searchField.cell as? NSSearchFieldCell)?.searchButtonCell = nil
        searchField.placeholderString = "Search"
        searchField.focusRingType = .none
        searchField.delegate = self
        searchField.sendsSearchStringImmediately = true
        searchField.setAccessibilityLabel("Search applications")
        searchField.translatesAutoresizingMaskIntoConstraints = false
    }

    private func configurePages() {
        pageViewport.wantsLayer = true
        pageViewport.layer?.masksToBounds = true
        pageViewport.translatesAutoresizingMaskIntoConstraints = false
        pageDocument.wantsLayer = true
        pageViewport.addSubview(pageDocument)
        pageViewport.onSwipe = { [weak self] deltaX in
            self?.movePage(by: deltaX < 0 ? 1 : -1)
        }
        pageDots.orientation = .horizontal
        pageDots.alignment = .centerY
        pageDots.spacing = 3
        pageDots.translatesAutoresizingMaskIntoConstraints = false
        emptyState.font = .systemFont(ofSize: 18, weight: .medium)
        emptyState.textColor = .white.withAlphaComponent(0.85)
        emptyState.alignment = .center
        emptyState.translatesAutoresizingMaskIntoConstraints = false
        emptyState.isHidden = true
    }

    private func rebuildPages() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        apps = catalog.apps.filter { app in
            query.isEmpty || app.name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
        currentPage = 0
        selectedIndex = nil
        emptyState.stringValue = query.isEmpty
            ? "No applications found."
            : "No applications found for “\(query)”\nTry another application name."
        layoutPages()
    }

    private func layoutPages(direction: Int = 0) {
        let size = pageViewport.bounds.size
        guard size.width > 0, size.height > 0 else { return }
        pageGeneration += 1
        let generation = pageGeneration
        let outgoing = pageDocument
        let slide = direction != 0 && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if !slide {
            isChangingPage = false
            queuedPage = nil
            pageViewport.subviews.forEach { $0.removeFromSuperview() }
        }
        pageDocument = FlippedView()
        pageDocument.wantsLayer = true
        pageViewport.addSubview(pageDocument)
        tiles.removeAll()
        pageDocument.frame = NSRect(origin: .zero, size: size)
        // Keep only the incoming and outgoing page during a slide; catalogs with many apps stay inexpensive to navigate.
        for index in grid.range(for: currentPage, count: apps.count) {
            let tile = AppTileButton(app: apps[index])
            tile.target = self
            tile.action = #selector(openApp(_:))
            tile.frame = grid.frame(at: index % grid.pageSize)
            tile.keyboardSelected = index == selectedIndex
            pageDocument.addSubview(tile)
            tiles[index] = tile
        }
        emptyState.isHidden = !apps.isEmpty
        pageDots.arrangedSubviews.forEach { pageDots.removeArrangedSubview($0); $0.removeFromSuperview() }
        for page in 0..<pageCount {
            let dot = PageDotButton()
            dot.tag = page
            dot.state = page == currentPage ? .on : .off
            dot.target = self
            dot.action = #selector(selectPage(_:))
            dot.setAccessibilityLabel("Page \(page + 1) of \(pageCount)")
            dot.toolTip = "Page \(page + 1) of \(pageCount)"
            pageDots.addArrangedSubview(dot)
        }
        if slide {
            isChangingPage = true
            let distance = size.width * (direction > 0 ? 1 : -1)
            pageDocument.setFrameOrigin(NSPoint(x: distance, y: 0))
            let incoming = pageDocument
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.38
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.20, 0.78, 0.25, 1)
                incoming.animator().setFrameOrigin(.zero)
                outgoing.animator().setFrameOrigin(NSPoint(x: -distance, y: 0))
            } completionHandler: { [weak self, weak outgoing] in
                Task { @MainActor in
                    outgoing?.removeFromSuperview()
                    guard let self, self.pageGeneration == generation else { return }
                    self.isChangingPage = false
                    if let next = self.queuedPage {
                        self.queuedPage = nil
                        self.showPage(at: next)
                    }
                }
            }
        }
    }

    @objc private func selectPage(_ sender: NSButton) {
        showPage(at: sender.tag)
    }

    func movePage(by direction: Int) {
        showPage(at: (queuedPage ?? currentPage) + direction)
    }

    private func showPage(at index: Int) {
        guard index >= 0, index < pageCount else { return }
        if isChangingPage {
            queuedPage = index
            return
        }
        guard index != currentPage else { return }
        let direction = index > currentPage ? 1 : -1
        currentPage = index
        if selectedIndex != nil { selectedIndex = currentPage * grid.pageSize }
        layoutPages(direction: direction)
    }

    func animatePresentation(visible: Bool, initial: Bool, duration: TimeInterval, reducedMotion: Bool) {
        view.layoutSubtreeIfNeeded()
        wallpaper.animateBlur(visible: visible, initial: initial, duration: duration, reducedMotion: reducedMotion)
        guard let layer = pageViewport.layer else { return }
        let center = NSPoint(x: pageViewport.bounds.midX, y: pageViewport.bounds.midY)
        func transform(_ scale: CGFloat) -> CATransform3D {
            var result = CATransform3DMakeTranslation(center.x, center.y, 0)
            result = CATransform3DScale(result, scale, scale, 1)
            return CATransform3DTranslate(result, -center.x, -center.y, 0)
        }
        let destination = transform(visible || reducedMotion ? 1 : 0.94)
        let origin = initial && !reducedMotion ? transform(0.94)
            : (layer.presentation()?.sublayerTransform ?? layer.sublayerTransform)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.sublayerTransform = destination
        CATransaction.commit()
        layer.removeAnimation(forKey: "launchpadZoom")
        guard !reducedMotion else { return }
        let zoom = CABasicAnimation(keyPath: "sublayerTransform")
        zoom.fromValue = NSValue(caTransform3D: origin)
        zoom.toValue = NSValue(caTransform3D: destination)
        zoom.duration = duration
        zoom.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.75, 0.25, 1)
        layer.add(zoom, forKey: "launchpadZoom")
    }

    func handleKey(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if modifiers == .command {
            switch event.keyCode {
            case 123: movePage(by: -1); return true
            case 124: movePage(by: 1); return true
            case 3:
                selectedIndex = nil
                updateSelection()
                view.window?.makeFirstResponder(searchField)
                searchField.selectText(nil)
                return true
            default: return false
            }
        }
        guard modifiers.isEmpty else { return false }
        // Preserve native text editing, including input-method composition.
        let editor = searchField.currentEditor()
        let editingSearch = editor != nil && view.window?.firstResponder === editor
        if let textView = editor as? NSTextView, textView.hasMarkedText() { return false }
        if editingSearch {
            if event.keyCode == 125 { selectApp(at: currentPage * grid.pageSize); return true }
            if event.keyCode == 36 || event.keyCode == 76 {
                if !searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    launchApp(at: currentPage * grid.pageSize)
                    return true
                }
            }
            return false
        }
        // Tab-focused controls keep native Space/Return handling.
        guard view.window?.firstResponder === pageViewport else { return false }
        switch event.keyCode {
        case 123, 124, 125, 126:
            let offset = event.keyCode == 123 ? -1 : event.keyCode == 124 ? 1 : event.keyCode == 125 ? grid.columns : -grid.columns
            let index = grid.movedIndex(from: selectedIndex ?? currentPage * grid.pageSize, by: offset, count: apps.count)
            if let index { selectApp(at: index) }
            return true
        case 36, 76:
            if let selectedIndex { launchApp(at: selectedIndex) }
            return true
        default:
            if let characters = event.characters, characters.unicodeScalars.contains(where: { CharacterSet.alphanumerics.contains($0) }) {
                selectedIndex = nil
                updateSelection()
                view.window?.makeFirstResponder(searchField)
            }
            return false
        }
    }

    private func selectApp(at index: Int) {
        guard apps.indices.contains(index) else { return }
        selectedIndex = index
        view.window?.makeFirstResponder(pageViewport)
        let page = index / grid.pageSize
        if page != currentPage {
            currentPage = page
            layoutPages()
        } else { updateSelection() }
        if let tile = tiles[index] {
            NSAccessibility.post(element: tile, notification: .focusedUIElementChanged)
        }
    }

    private func updateSelection() {
        for (index, tile) in tiles { tile.keyboardSelected = selectedIndex == index }
    }

    @objc private func openApp(_ sender: AppTileButton) {
        guard let app = sender.launchpadApp else { return }
        launch(app)
    }

    private func launchApp(at index: Int) {
        guard apps.indices.contains(index) else { return }
        launch(apps[index])
    }

    private func launch(_ app: LaunchpadApp) {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: app.path), configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    let alert = NSAlert()
                    alert.messageText = "Couldn’t open \(app.name)"
                    alert.informativeText = error.localizedDescription
                    if let window = self.view.window { alert.beginSheetModal(for: window) }
                } else { self.dismiss() }
            }
        }
    }

    private func pin(_ child: NSView, to parent: NSView) {
        NSLayoutConstraint.activate([
            child.topAnchor.constraint(equalTo: parent.topAnchor),
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            child.bottomAnchor.constraint(equalTo: parent.bottomAnchor)
        ])
    }
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class PagingViewportView: NSView {
    override var acceptsFirstResponder: Bool { true }
    var onSwipe: ((CGFloat) -> Void)?
    private var scroll = PageScrollAccumulator()

    override func swipe(with event: NSEvent) {
        if event.deltaX != 0 { onSwipe?(event.deltaX) }
    }

    override func scrollWheel(with event: NSEvent) {
        if let delta = scroll.consume(
            deltaX: event.scrollingDeltaX,
            deltaY: event.scrollingDeltaY,
            began: event.phase.contains(.began),
            ended: event.phase.contains(.ended) || event.phase.contains(.cancelled),
            isMomentum: !event.momentumPhase.isEmpty,
            isDiscrete: event.phase.isEmpty && event.momentumPhase.isEmpty,
            timestamp: event.timestamp
        ) { onSwipe?(delta) }
    }
}

final class PageDotButton: NSButton {
    init() {
        super.init(frame: .zero)
        isBordered = false
        title = ""
        setButtonType(.momentaryChange)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 16).isActive = true
        heightAnchor.constraint(equalToConstant: 18).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.withAlphaComponent(state == .on ? 0.95 : 0.32).setFill()
        NSBezierPath(ovalIn: NSRect(x: (bounds.width - 5) / 2, y: (bounds.height - 5) / 2, width: 5, height: 5)).fill()
    }
}

/// Use the user's actual wallpaper, so the launcher feels like part of the desktop.
final class WallpaperView: NSView {
    private let sharpLayer = CALayer()
    private let blurredLayer = CALayer()
    private let dimmerLayer = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        let background = CAGradientLayer()
        background.colors = [
            NSColor(red: 0.16, green: 0.08, blue: 0.35, alpha: 1).cgColor,
            NSColor(red: 0.12, green: 0.25, blue: 0.48, alpha: 1).cgColor
        ]
        layer = background
        for imageLayer in [sharpLayer, blurredLayer] {
            imageLayer.contentsGravity = .resizeAspectFill
            imageLayer.masksToBounds = true
            background.addSublayer(imageLayer)
        }
        dimmerLayer.backgroundColor = NSColor.black.withAlphaComponent(0.20).cgColor
        background.addSublayer(dimmerLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for imageLayer in [sharpLayer, blurredLayer, dimmerLayer] { imageLayer.frame = bounds }
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let screen = window?.screen,
              let url = NSWorkspace.shared.desktopImageURL(for: screen),
              let source = NSImage(contentsOf: url) else { return }
        let size = NSSize(width: 1600, height: max(1, 1600 * source.size.height / max(1, source.size.width)))
        let thumbnail = NSImage(size: size)
        thumbnail.lockFocus()
        source.draw(in: NSRect(origin: .zero, size: size))
        thumbnail.unlockFocus()
        guard let data = thumbnail.tiffRepresentation, let input = CIImage(data: data) else { return }
        let context = CIContext()
        let blurred = input.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 18]).cropped(to: input.extent)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sharpLayer.contents = context.createCGImage(input, from: input.extent)
        blurredLayer.contents = context.createCGImage(blurred, from: input.extent)
        CATransaction.commit()
    }

    func animateBlur(visible: Bool, initial: Bool, duration: TimeInterval, reducedMotion: Bool) {
        // Crossfade pre-rendered sharp/blurred images; no expensive filter runs per frame.
        let origin = initial ? Float(0) : (blurredLayer.presentation()?.opacity ?? blurredLayer.opacity)
        let destination: Float = visible ? 1 : 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        blurredLayer.opacity = destination
        CATransaction.commit()
        blurredLayer.removeAnimation(forKey: "wallpaperBlur")
        guard !reducedMotion else { return }
        let blur = CABasicAnimation(keyPath: "opacity")
        blur.fromValue = origin
        blur.toValue = destination
        blur.duration = duration
        blur.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        blurredLayer.add(blur, forKey: "wallpaperBlur")
    }
}

final class AppTileButton: NSButton {
    override var isFlipped: Bool { false }
    let launchpadApp: LaunchpadApp?
    var keyboardSelected = false { didSet { needsDisplay = true } }

    init(app: LaunchpadApp) {
        launchpadApp = app
        super.init(frame: .zero)
        title = app.name
        toolTip = app.name
        isBordered = false
        setButtonType(.momentaryPushIn)
        setAccessibilityLabel(app.name)
        setAccessibilityHelp("Open \(app.name)")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        let background = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 14, yRadius: 14)
        if isHighlighted || keyboardSelected {
            NSColor.white.withAlphaComponent(isHighlighted ? 0.23 : 0.11).setFill()
            background.fill()
        }
        if keyboardSelected {
            NSColor.white.withAlphaComponent(0.70).setStroke()
            background.lineWidth = 2
            background.stroke()
        }
        let iconSize = max(0, min(88, bounds.width - 24, bounds.height - 40))
        let labelY = max(4, (bounds.height - iconSize - 26) / 2)
        launchpadApp?.icon.draw(in: NSRect(x: (bounds.width - iconSize) / 2, y: labelY + 24, width: iconSize, height: iconSize), from: .zero, operation: .sourceOver, fraction: isHighlighted ? 0.75 : 1)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph
        ]
        (title as NSString).draw(in: NSRect(x: 3, y: labelY, width: bounds.width - 6, height: 18), withAttributes: attributes)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let launchpad = LaunchpadController()
    private var statusItem: NSStatusItem?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        installMainMenu()
        installStatusItem()
        registerHotKey()
        launchpad.show()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        launchpad.show()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "OldLaunchpad")
        appMenu.addItem(withTitle: "Quit OldLaunchpad", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "square.grid.3x3.fill", accessibilityDescription: "Old Launchpad")

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show OldLaunchpad", action: #selector(showFromMenuBar), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Hide OldLaunchpad", action: #selector(hideFromMenuBar), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit OldLaunchpad", action: #selector(quitFromMenuBar), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }

        item.menu = menu
        statusItem = item
    }

    @objc private func showFromMenuBar() {
        launchpad.show()
    }

    @objc private func hideFromMenuBar() {
        launchpad.hide()
    }

    @objc private func quitFromMenuBar() {
        NSApp.terminate(nil)
    }

    private func registerHotKey() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }

                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                if hotKeyID.id == 1 {
                    let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                    Task { @MainActor in
                        delegate.launchpad.toggle()
                    }
                }

                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )

        let hotKeyID = EventHotKeyID(signature: OSType(0x4F4C5044), id: 1)
        RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(controlKey | optionKey | cmdKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
