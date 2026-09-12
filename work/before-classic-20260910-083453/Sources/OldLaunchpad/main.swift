import AppKit
import Carbon

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
                loaded.append(makeApp(from: url))
            }
        }

        apps = loaded.sorted { (app1, app2) in
        app1.name.localizedCaseInsensitiveCompare(app2.name) == .orderedAscending
    }
    }

    private func makeApp(from url: URL) -> LaunchpadApp {
        let infoURL = url.appendingPathComponent("Contents/Info.plist")
        let info = NSDictionary(contentsOf: infoURL) as? [String: Any]
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

    func toggle() {
        if window?.isVisible == true {
            hide()
        } else {
            show()
        }
    }

    func show() {
        guard window?.isVisible != true else {
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
            return
        }

        catalog.reload()

        let screenFrame = NSScreen.main?.frame
            ?? NSScreen.screens.first?.frame
            ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let panel = OverlayWindow(
            contentRect: screenFrame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.contentViewController = LaunchpadViewController(catalog: catalog) { [weak self] in
            self?.hide()
        }
        panel.minSize = screenFrame.size
        panel.maxSize = screenFrame.size
        panel.setFrame(screenFrame, display: false)

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.hide()
                return nil
            }

            if event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
                let launchpadViewController = self?.window?.contentViewController as? LaunchpadViewController
                if event.keyCode == 123 {
                    launchpadViewController?.movePage(by: -1)
                    return nil
                }
                if event.keyCode == 124 {
                    launchpadViewController?.movePage(by: 1)
                    return nil
                }
            }

            return event
        }

        window = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    func hide() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }

        window?.orderOut(nil)
        window = nil
    }
}

final class LaunchpadViewController: NSViewController, NSSearchFieldDelegate {
    private let catalog: AppCatalog
    private let dismiss: () -> Void
    private let searchField = PagingSearchField()
    private let searchBackground = NSView()
    private let categoryStack = NSStackView()
    private let pageViewport = PagingViewportView()
    private let pageDocument = FlippedView()
    private let pageIndicator = NSTextField(labelWithString: "")
    private var selectedCategory = "All"
    private var pages: [[LaunchpadApp]] = []
    private var currentPage = 0
    private var lastViewportSize = NSSize.zero
    private var navigationMonitor: Any?

    private let columns = 6
    private let rows = 4
    private var pageSize: Int { columns * rows }

    init(catalog: AppCatalog, dismiss: @escaping () -> Void) {
        self.catalog = catalog
        self.dismiss = dismiss
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true

        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(blur)
        pin(blur, to: view)

        let dimmer = NSView()
        dimmer.wantsLayer = true
        dimmer.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.48).cgColor
        dimmer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dimmer)
        pin(dimmer, to: view)

        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(content)

        configureSearchField()
        searchBackground.translatesAutoresizingMaskIntoConstraints = false
        searchBackground.wantsLayer = true
        searchBackground.layer?.cornerRadius = 28
        searchBackground.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.56).cgColor
        searchBackground.layer?.borderWidth = 1
        searchBackground.layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
        content.addSubview(searchBackground)
        searchBackground.addSubview(searchField)

        configureCategories()
        content.addSubview(categoryStack)

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(divider)

        configurePages()
        content.addSubview(pageViewport)
        content.addSubview(pageIndicator)

        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: view.topAnchor, constant: 72),
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 34),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -34),
            content.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -28),
            searchBackground.topAnchor.constraint(equalTo: content.topAnchor),
            searchBackground.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            searchBackground.widthAnchor.constraint(equalToConstant: 720),
            searchBackground.heightAnchor.constraint(equalToConstant: 58),
            searchBackground.leadingAnchor.constraint(greaterThanOrEqualTo: content.leadingAnchor),
            searchBackground.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor),
            searchField.centerYAnchor.constraint(equalTo: searchBackground.centerYAnchor),
            searchField.leadingAnchor.constraint(equalTo: searchBackground.leadingAnchor, constant: 16),
            searchField.trailingAnchor.constraint(equalTo: searchBackground.trailingAnchor, constant: -16),
            searchField.heightAnchor.constraint(equalToConstant: 32),
            categoryStack.topAnchor.constraint(equalTo: searchBackground.bottomAnchor, constant: 18),
            categoryStack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            categoryStack.heightAnchor.constraint(equalToConstant: 38),
            divider.topAnchor.constraint(equalTo: categoryStack.bottomAnchor, constant: 18),
            divider.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            pageViewport.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 16),
            pageViewport.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            pageViewport.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            pageViewport.bottomAnchor.constraint(equalTo: pageIndicator.topAnchor, constant: -8),
            pageIndicator.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            pageIndicator.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        searchField.becomeFirstResponder()
        rebuildPages(resetPage: true)
        installNavigationMonitor()
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        removeNavigationMonitor()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        guard pageViewport.bounds.size != lastViewportSize else { return }
        lastViewportSize = pageViewport.bounds.size
        layoutPages()
    }

    func controlTextDidChange(_ notification: Notification) {
        rebuildPages(resetPage: true)
    }

    private func configureSearchField() {
        searchField.placeholderString = "Applications"
        searchField.font = .systemFont(ofSize: 22, weight: .regular)
        searchField.textColor = .white.withAlphaComponent(0.9)
        searchField.drawsBackground = false
        searchField.isBordered = false
        searchField.placeholderString = "Search applications"
        searchField.focusRingType = .none
        searchField.delegate = self
        searchField.onPageNavigation = { [weak self] direction in
            self?.movePage(by: direction)
        }
        searchField.translatesAutoresizingMaskIntoConstraints = false
    }

    private func configureCategories() {
        categoryStack.orientation = .horizontal
        categoryStack.spacing = 12
        categoryStack.alignment = .centerY
        categoryStack.translatesAutoresizingMaskIntoConstraints = false

        for category in catalog.categories {
            let button = PillButton(title: category)
            button.target = self
            button.action = #selector(selectCategory(_:))
            button.identifier = NSUserInterfaceItemIdentifier(category)
            categoryStack.addArrangedSubview(button)
            update(button: button, selected: category == selectedCategory)
        }
    }

    private func configurePages() {
        pageViewport.wantsLayer = true
        pageViewport.layer?.masksToBounds = true
        pageViewport.translatesAutoresizingMaskIntoConstraints = false

        pageDocument.wantsLayer = true
        pageViewport.addSubview(pageDocument)

        pageViewport.onSwipe = { [weak self] deltaX in
            guard let self else { return }
            if deltaX < 0 {
                self.showPage(at: self.currentPage + 1, animated: true)
            } else if deltaX > 0 {
                self.showPage(at: self.currentPage - 1, animated: true)
            }
        }

        pageIndicator.alignment = .center
        pageIndicator.font = .systemFont(ofSize: 14, weight: .medium)
        pageIndicator.textColor = .white.withAlphaComponent(0.62)
        pageIndicator.translatesAutoresizingMaskIntoConstraints = false
    }

    @objc private func selectCategory(_ sender: NSButton) {
        selectedCategory = sender.identifier?.rawValue ?? "All"
        for case let button as PillButton in categoryStack.arrangedSubviews {
            update(button: button, selected: button.identifier?.rawValue == selectedCategory)
        }
        rebuildPages(resetPage: true)
    }

    private func filteredApps() -> [LaunchpadApp] {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return catalog.apps.filter { app in
            let categoryMatches = selectedCategory == "All" || app.category == selectedCategory
            let searchMatches = query.isEmpty || app.name.localizedCaseInsensitiveContains(query)
            return categoryMatches && searchMatches
        }
    }

    private func rebuildPages(resetPage: Bool) {
        let apps = filteredApps().sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        pages = stride(from: 0, to: apps.count, by: pageSize).map {
            Array(apps[$0..<min($0 + pageSize, apps.count)])
        }
        if resetPage {
            currentPage = 0
        } else {
            currentPage = min(currentPage, max(0, pages.count - 1))
        }
        layoutPages()
    }

    private func layoutPages() {
        let viewportSize = pageViewport.bounds.size
        guard viewportSize.width > 0, viewportSize.height > 0 else { return }

        pageDocument.subviews.forEach { $0.removeFromSuperview() }
        pageDocument.frame = NSRect(
            x: -CGFloat(currentPage) * viewportSize.width,
            y: 0,
            width: max(viewportSize.width, viewportSize.width * CGFloat(pages.count)),
            height: viewportSize.height
        )

        let tileSize = NSSize(width: 140, height: 112)
        let horizontalGap = max(16, (viewportSize.width - CGFloat(columns) * tileSize.width) / CGFloat(columns + 1))
        let verticalGap = max(16, min(48, (viewportSize.height - CGFloat(rows) * tileSize.height) / CGFloat(rows + 1)))

        for (pageIndex, apps) in pages.enumerated() {
            let page = FlippedView(frame: NSRect(
                x: CGFloat(pageIndex) * viewportSize.width,
                y: 0,
                width: viewportSize.width,
                height: viewportSize.height
            ))
            pageDocument.addSubview(page)

            for (index, app) in apps.enumerated() {
                let column = index % columns
                let row = index / columns
                let tile = AppTileButton(app: app)
                tile.target = self
                tile.action = #selector(openApp(_:))
                tile.frame = NSRect(
                    x: horizontalGap + CGFloat(column) * (tileSize.width + horizontalGap),
                    y: verticalGap + CGFloat(row) * (tileSize.height + verticalGap),
                    width: tileSize.width,
                    height: tileSize.height
                )
                page.addSubview(tile)
            }
        }

        updatePageControls()
    }

    private func updatePageControls() {
        let pageCount = pages.count
        pageIndicator.stringValue = pageCount > 0 ? "\(currentPage + 1) / \(pageCount)" : "No matching applications"
    }

    private func showPage(at index: Int, animated: Bool) {
        guard pages.indices.contains(index), index != currentPage else { return }
        let previousPage = currentPage
        currentPage = index
        let origin = NSPoint(x: -CGFloat(currentPage) * pageViewport.bounds.width, y: 0)

        if animated, let layer = pageViewport.layer {
            let transition = CATransition()
            transition.type = .push
            transition.subtype = index > previousPage ? .fromRight : .fromLeft
            transition.duration = 0.22
            transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(transition, forKey: "pageTransition")
        }
        pageDocument.setFrameOrigin(origin)

        updatePageControls()
    }

    func movePage(by direction: Int) {
        showPage(at: currentPage + direction, animated: true)
    }

    private func installNavigationMonitor() {
        guard navigationMonitor == nil else { return }
        navigationMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty else {
                return event
            }

            switch event.keyCode {
            case 123:
                self.showPage(at: self.currentPage - 1, animated: true)
                return nil
            case 124:
                self.showPage(at: self.currentPage + 1, animated: true)
                return nil
            default:
                return event
            }
        }
    }

    private func removeNavigationMonitor() {
        if let navigationMonitor {
            NSEvent.removeMonitor(navigationMonitor)
            self.navigationMonitor = nil
        }
    }

    private func update(button: PillButton, selected: Bool) {
        button.layer?.backgroundColor = NSColor.white.withAlphaComponent(selected ? 0.18 : 0.09).cgColor
        button.attributedTitle = NSAttributedString(
            string: button.title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 16, weight: .semibold),
                .foregroundColor: NSColor.white.withAlphaComponent(selected ? 0.95 : 0.68)
            ]
        )
    }

    @objc private func openApp(_ sender: AppTileButton) {
        guard let app = sender.launchpadApp else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: app.path), configuration: configuration)
        dismiss()
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

final class PagingSearchField: NSSearchField {
    var onPageNavigation: ((Int) -> Void)?

    override func keyDown(with event: NSEvent) {
        guard event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty else {
            super.keyDown(with: event)
            return
        }

        switch event.keyCode {
        case 123:
            onPageNavigation?(-1)
        case 124:
            onPageNavigation?(1)
        default:
            super.keyDown(with: event)
        }
    }
}

final class PagingViewportView: NSView {
    var onSwipe: ((CGFloat) -> Void)?
    private var horizontalScrollDelta: CGFloat = 0
    private var hasChangedPageInCurrentGesture = false

    override func swipe(with event: NSEvent) {
        onSwipe?(event.deltaX)
    }

    override func scrollWheel(with event: NSEvent) {
        let deltaX = event.scrollingDeltaX
        guard abs(deltaX) > abs(event.scrollingDeltaY) else {
            super.scrollWheel(with: event)
            return
        }

        if event.phase == .began {
            horizontalScrollDelta = 0
            hasChangedPageInCurrentGesture = false
        }
        horizontalScrollDelta += deltaX

        if !hasChangedPageInCurrentGesture, abs(horizontalScrollDelta) >= 40 {
            hasChangedPageInCurrentGesture = true
            onSwipe?(horizontalScrollDelta)
            horizontalScrollDelta = 0
        }

        if event.momentumPhase == .ended {
            hasChangedPageInCurrentGesture = false
            horizontalScrollDelta = 0
        }
    }
}

final class PillButton: NSButton {
    init(title: String) {
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 19
        contentTintColor = .white
        alignment = .center
        lineBreakMode = .byTruncatingTail
        translatesAutoresizingMaskIntoConstraints = false
        setButtonType(.momentaryChange)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 38),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 92)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        let textSize = attributedTitle.size()
        let textRect = NSRect(
            x: max(0, (bounds.width - textSize.width) / 2),
            y: (bounds.height - textSize.height) / 2,
            width: min(textSize.width, bounds.width),
            height: textSize.height
        )
        attributedTitle.draw(in: textRect)
    }
}

final class AppTileButton: NSButton {
    let launchpadApp: LaunchpadApp?

    init(app: LaunchpadApp) {
        launchpadApp = app
        super.init(frame: .zero)
        title = app.name
        image = app.icon
        imagePosition = .imageAbove
        imageScaling = .scaleProportionallyUpOrDown
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 8
        alignment = .center
        font = .systemFont(ofSize: 16, weight: .semibold)
        contentTintColor = .white
        attributedTitle = NSAttributedString(
            string: app.name,
            attributes: [
                .font: NSFont.systemFont(ofSize: 16, weight: .semibold),
                .foregroundColor: NSColor.white
            ]
        )
        translatesAutoresizingMaskIntoConstraints = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
        installStatusItem()
        registerHotKey()
        launchpad.show()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
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
