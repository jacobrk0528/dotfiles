// GlassBar — a full-width Liquid Glass bar along the bottom of every screen.
//
//   left:   yabai spaces on that display (click to switch)
//   center: Dock-pinned apps + other running apps (click to open/focus)
// Clock and battery stay in the menu bar.
//
// Pinned apps are read from the Dock's own pin list, so pin/unpin by dragging
// in and out of the (auto-hidden) Dock. Drag icons within the bar to reorder
// them; that order is saved in GlassBar's own defaults and survives restarts. Built and installed by install.sh.
// yabai pokes it with SIGUSR1 (see mac/yabai/yabairc) when windows come and go.

import AppKit

let barHeight: CGFloat = 78
let barMargin: CGFloat = 8     // gap between the bar and the screen edges
let iconSize: CGFloat = 64
let yabaiPath = "/opt/homebrew/bin/yabai"

// MARK: - yabai

struct YabaiSpace: Decodable {
    let index: Int
    let display: Int
    let windows: [Int]
    let isVisible: Bool
    let hasFocus: Bool

    enum CodingKeys: String, CodingKey {
        case index, display, windows
        case isVisible = "is-visible"
        case hasFocus = "has-focus"
    }
}

struct YabaiWindow: Decodable {
    let id: Int
    let pid: Int32
    let title: String
    let subrole: String
    let isMinimized: Bool

    enum CodingKeys: String, CodingKey {
        case id, pid, title, subrole
        case isMinimized = "is-minimized"
    }
}

struct YabaiDisplay: Decodable {
    let id: UInt32
    let index: Int
}

enum Yabai {
    static func run(_ args: [String]) -> Data? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: yabaiPath)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return p.terminationStatus == 0 ? data : nil
    }

    /// Spaces grouped by CGDirectDisplayID, so each bar can find its own.
    static func spacesByDisplay() -> [UInt32: [YabaiSpace]] {
        guard let d = run(["-m", "query", "--displays"]),
              let s = run(["-m", "query", "--spaces"]),
              let displays = try? JSONDecoder().decode([YabaiDisplay].self, from: d),
              let spaces = try? JSONDecoder().decode([YabaiSpace].self, from: s)
        else { return [:] }
        var byIndex: [Int: UInt32] = [:]
        for disp in displays { byIndex[disp.index] = disp.id }
        var result: [UInt32: [YabaiSpace]] = [:]
        for sp in spaces {
            if let id = byIndex[sp.display] { result[id, default: []].append(sp) }
        }
        return result
    }

    static func focus(space: Int) {
        DispatchQueue.global().async { _ = run(["-m", "space", "--focus", String(space)]) }
    }

    static func windows(pid: Int32) -> [YabaiWindow] {
        guard let d = run(["-m", "query", "--windows"]),
              let all = try? JSONDecoder().decode([YabaiWindow].self, from: d)
        else { return [] }
        // Skip helper/popup windows apps keep around; the Dock doesn't list those either
        return all.filter { $0.pid == pid && $0.subrole == "AXStandardWindow" && !$0.title.isEmpty }
    }

    static func focus(window: Int) {
        DispatchQueue.global().async { _ = run(["-m", "window", "--focus", String(window)]) }
    }
}

// MARK: - Apps

struct BarApp {
    let bundleID: String
    let url: URL
    let running: NSRunningApplication?
    let pinned: Bool
}

enum Apps {
    static let dockDomain = "com.apple.dock" as CFString
    static let pinsKey = "persistent-apps" as CFString

    static func dockItems() -> [[String: Any]] {
        CFPreferencesAppSynchronize(dockDomain)   // pick up edits made by the Dock
        return CFPreferencesCopyAppValue(pinsKey, dockDomain) as? [[String: Any]] ?? []
    }

    /// Bundle IDs pinned in the Dock, in Dock order.
    static func dockPins() -> [String] {
        dockItems().compactMap { ($0["tile-data"] as? [String: Any])?["bundle-identifier"] as? String }
    }

    /// Keep in Dock / Remove from Dock: edit the Dock's pin list and restart it.
    static func setPinned(_ app: BarApp, _ pin: Bool) {
        var items = dockItems().filter {
            ($0["tile-data"] as? [String: Any])?["bundle-identifier"] as? String != app.bundleID
        }
        if pin {
            items.append([
                "tile-type": "file-tile",
                "tile-data": [
                    "bundle-identifier": app.bundleID,
                    "file-data": ["_CFURLString": app.url.absoluteString, "_CFURLStringType": 15],
                ],
            ])
        }
        CFPreferencesSetAppValue(pinsKey, items as CFArray, dockDomain)
        CFPreferencesAppSynchronize(dockDomain)
        let killDock = Process()
        killDock.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        killDock.arguments = ["Dock"]
        try? killDock.run()
        NotificationCenter.default.post(name: Order.changed, object: nil)
    }

    static func current() -> [BarApp] {
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        var byID: [String: NSRunningApplication] = [:]
        for app in running { if let id = app.bundleIdentifier, byID[id] == nil { byID[id] = app } }

        var result: [BarApp] = []
        var seen = Set<String>()
        for id in dockPins() where !seen.contains(id) {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { continue }
            result.append(BarApp(bundleID: id, url: url, running: byID[id], pinned: true))
            seen.insert(id)
        }
        for app in running {
            guard let id = app.bundleIdentifier, !seen.contains(id), let url = app.bundleURL else { continue }
            result.append(BarApp(bundleID: id, url: url, running: app, pinned: false))
            seen.insert(id)
        }
        // Apply the drag-and-drop order; apps never dragged keep their
        // pins-then-running position after the ordered ones.
        let rank = Dictionary(Order.saved().enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        return result.enumerated()
            .sorted { (rank[$0.element.bundleID] ?? Int.max, $0.offset) < (rank[$1.element.bundleID] ?? Int.max, $1.offset) }
            .map(\.element)
    }
}

enum Order {
    static let key = "appOrder"
    static let changed = Notification.Name("GlassBarOrderChanged")

    static func saved() -> [String] { UserDefaults.standard.stringArray(forKey: key) ?? [] }

    /// Save the order currently shown, keeping any saved apps that aren't on
    /// the bar right now (e.g. quit) after them so they aren't forgotten.
    static func save(visible: [String]) {
        let rest = saved().filter { !visible.contains($0) }
        UserDefaults.standard.set(visible + rest, forKey: key)
        NotificationCenter.default.post(name: changed, object: nil)
    }
}

// MARK: - Views

/// Invisible button that just forwards clicks; the look comes from its subviews.
/// Views that set onDragMoved can also be dragged; a drag never counts as a click.
class ClickView: NSView {
    var onClick: (() -> Void)?
    var menuProvider: (() -> NSMenu?)?
    var onDragMoved: ((NSEvent) -> Void)?
    var onDragEnded: (() -> Void)?
    private var downPoint: NSPoint?
    private var dragging = false

    override func mouseDown(with event: NSEvent) {
        downPoint = event.locationInWindow
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let onDragMoved, let start = downPoint else { return }
        if !dragging, hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) > 4 {
            dragging = true
            alphaValue = 0.6
        }
        if dragging { onDragMoved(event) }
    }

    override func mouseUp(with event: NSEvent) {
        if dragging {
            dragging = false
            alphaValue = 1
            onDragEnded?()
        } else if bounds.contains(convert(event.locationInWindow, from: nil)) {
            onClick?()
        }
        downPoint = nil
    }
    override func menu(for event: NSEvent) -> NSMenu? { menuProvider?() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class AppTile: ClickView {
    var bundleID = ""
}

func appTile(_ app: BarApp) -> AppTile {
    let tile = AppTile()
    tile.bundleID = app.bundleID
    tile.toolTip = FileManager.default.displayName(atPath: app.url.path).replacingOccurrences(of: ".app", with: "")
    tile.translatesAutoresizingMaskIntoConstraints = false

    let icon = NSImageView(image: NSWorkspace.shared.icon(forFile: app.url.path))
    icon.imageScaling = .scaleProportionallyUpOrDown
    icon.translatesAutoresizingMaskIntoConstraints = false
    tile.addSubview(icon)

    let dot = NSView()
    dot.wantsLayer = true
    dot.layer?.cornerRadius = 2
    dot.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.8).cgColor
    dot.isHidden = app.running == nil
    dot.translatesAutoresizingMaskIntoConstraints = false
    tile.addSubview(dot)

    NSLayoutConstraint.activate([
        tile.widthAnchor.constraint(equalToConstant: iconSize + 6),
        tile.heightAnchor.constraint(equalToConstant: barHeight),
        icon.widthAnchor.constraint(equalToConstant: iconSize),
        icon.heightAnchor.constraint(equalToConstant: iconSize),
        icon.centerXAnchor.constraint(equalTo: tile.centerXAnchor),
        icon.centerYAnchor.constraint(equalTo: tile.centerYAnchor, constant: -2),
        dot.widthAnchor.constraint(equalToConstant: 4),
        dot.heightAnchor.constraint(equalToConstant: 4),
        dot.centerXAnchor.constraint(equalTo: tile.centerXAnchor),
        dot.bottomAnchor.constraint(equalTo: tile.bottomAnchor, constant: -2),
    ])

    tile.onClick = {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: app.url, configuration: config)
    }
    tile.menuProvider = { appMenu(app) }
    return tile
}

/// Right-click menu, modeled on the Dock's. Apps' own Dock menu items (e.g.
/// Brave's "New Incognito Window") only reach the real Dock, so they're missing.
func appMenu(_ app: BarApp) -> NSMenu {
    let menu = NSMenu()
    // Actions are retained by their items (see MenuAction)
    func add(_ title: String, _ action: @escaping () -> Void) -> NSMenuItem {
        let item = MenuAction(title: title, action: action).item
        menu.addItem(item)
        return item
    }

    if let running = app.running {
        let windows = Yabai.windows(pid: running.processIdentifier)
        if !windows.isEmpty {
            menu.addItem(NSMenuItem.sectionHeader(title: "Windows"))
            let fallback = running.localizedName ?? "Window"
            for w in windows {
                let title = w.title.isEmpty ? fallback : w.title
                _ = add(w.isMinimized ? "\(title) (minimized)" : title) { Yabai.focus(window: w.id) }
            }
            menu.addItem(.separator())
        }
    }

    _ = add(app.pinned ? "Remove from Dock" : "Keep in Dock") { Apps.setPinned(app, !app.pinned) }
    _ = add("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([app.url]) }

    if let running = app.running {
        menu.addItem(.separator())
        _ = add(running.isHidden ? "Show" : "Hide") {
            if running.isHidden { running.unhide() } else { running.hide() }
        }
        _ = add("Quit") { running.terminate() }
    } else {
        menu.addItem(.separator())
        _ = add("Open") {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: app.url, configuration: config)
        }
    }
    return menu
}

/// NSMenuItem with a closure instead of a target/selector pair.
final class MenuAction: NSObject {
    let item: NSMenuItem
    private let action: () -> Void
    init(title: String, action: @escaping () -> Void) {
        self.action = action
        self.item = NSMenuItem(title: title, action: #selector(fire), keyEquivalent: "")
        super.init()
        item.target = self
        item.representedObject = self   // keep self alive as long as the item
    }
    @objc private func fire() { action() }
}

func spaceTile(_ space: YabaiSpace, label: Int) -> NSView {
    let tile = ClickView()
    tile.wantsLayer = true
    tile.layer?.cornerRadius = 8
    tile.translatesAutoresizingMaskIntoConstraints = false
    if space.isVisible {
        tile.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.18).cgColor
    }

    let text = NSTextField(labelWithString: String(label))
    text.font = .monospacedDigitSystemFont(ofSize: 13, weight: space.isVisible ? .bold : .medium)
    text.textColor = space.windows.isEmpty && !space.isVisible ? .tertiaryLabelColor : .labelColor
    text.translatesAutoresizingMaskIntoConstraints = false
    tile.addSubview(text)

    NSLayoutConstraint.activate([
        tile.widthAnchor.constraint(equalToConstant: 28),
        tile.heightAnchor.constraint(equalToConstant: 28),
        text.centerXAnchor.constraint(equalTo: tile.centerXAnchor),
        text.centerYAnchor.constraint(equalTo: tile.centerYAnchor),
    ])
    tile.onClick = { Yabai.focus(space: space.index) }
    return tile
}

// MARK: - App picker

/// Background of the bar: right-clicking empty space opens the app picker.
final class BarBackground: NSView {
    override func rightMouseDown(with event: NSEvent) {
        AppPicker.shared.show(on: window?.screen)
    }
}

struct InstalledApp {
    let name: String
    let bundleID: String
    let url: URL
}

enum Installed {
    static let folders = ["/Applications", "/Applications/Utilities", "/System/Applications",
                          "/System/Applications/Utilities", NSHomeDirectory() + "/Applications"]

    static func scan() -> [InstalledApp] {
        var seen = Set<String>()
        var apps: [InstalledApp] = []
        for folder in folders {
            let dir = URL(fileURLWithPath: folder)
            let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            for url in urls where url.pathExtension == "app" {
                guard let id = Bundle(url: url)?.bundleIdentifier, !seen.contains(id) else { continue }
                seen.insert(id)
                let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
                apps.append(InstalledApp(name: name, bundleID: id, url: url))
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

final class AppPickerItem: NSCollectionViewItem {
    static let id = NSUserInterfaceItemIdentifier("AppPickerItem")
    let icon = NSImageView()
    let label = NSTextField(labelWithString: "")

    override func loadView() {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.cornerRadius = 10
        icon.imageScaling = .scaleProportionallyUpOrDown
        label.alignment = .center
        label.font = .systemFont(ofSize: 11)
        label.lineBreakMode = .byTruncatingTail
        for sub in [icon, label] {
            sub.translatesAutoresizingMaskIntoConstraints = false
            v.addSubview(sub)
        }
        NSLayoutConstraint.activate([
            icon.topAnchor.constraint(equalTo: v.topAnchor, constant: 8),
            icon.centerXAnchor.constraint(equalTo: v.centerXAnchor),
            icon.widthAnchor.constraint(equalToConstant: 56),
            icon.heightAnchor.constraint(equalToConstant: 56),
            label.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 4),
            label.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -4),
        ])
        view = v
    }

    override var isSelected: Bool {
        didSet { view.layer?.backgroundColor = isSelected ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.4).cgColor : nil }
    }
}

/// "Add to Dock" window: every installed app that isn't pinned yet, with a
/// search box. Click one (or Return on the first match) to pin it.
final class AppPicker: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate, NSSearchFieldDelegate, NSWindowDelegate {
    static let shared = AppPicker()

    private var panel: NSPanel?
    private let grid = NSCollectionView()
    private let search = NSSearchField()
    private var all: [InstalledApp] = []
    private var shown: [InstalledApp] = []

    func show(on screen: NSScreen?) {
        let pinned = Set(Apps.dockPins())
        all = Installed.scan().filter { !pinned.contains($0.bundleID) }
        search.stringValue = ""
        filter()

        let panel = self.panel ?? makePanel()
        self.panel = panel
        if let visible = (screen ?? NSScreen.main)?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: visible.midX - panel.frame.width / 2,
                                         y: visible.midY - panel.frame.height / 2))
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(search)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 620, height: 480),
                            styleMask: [.titled, .closable, .fullSizeContentView],
                            backing: .buffered, defer: false)
        panel.title = "Add to Dock"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = true
        panel.delegate = self

        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 96, height: 96)
        layout.minimumInteritemSpacing = 4
        layout.minimumLineSpacing = 4
        layout.sectionInset = NSEdgeInsets(top: 8, left: 12, bottom: 12, right: 12)
        grid.collectionViewLayout = layout
        grid.isSelectable = true
        grid.backgroundColors = [.clear]
        grid.dataSource = self
        grid.delegate = self
        grid.register(AppPickerItem.self, forItemWithIdentifier: AppPickerItem.id)

        let scroll = NSScrollView()
        scroll.documentView = grid
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false

        search.placeholderString = "Search apps"
        search.delegate = self

        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.state = .active
        for sub in [search, scroll] as [NSView] {
            sub.translatesAutoresizingMaskIntoConstraints = false
            blur.addSubview(sub)
        }
        NSLayoutConstraint.activate([
            search.topAnchor.constraint(equalTo: blur.topAnchor, constant: 36),
            search.leadingAnchor.constraint(equalTo: blur.leadingAnchor, constant: 16),
            search.trailingAnchor.constraint(equalTo: blur.trailingAnchor, constant: -16),
            scroll.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
        ])
        panel.contentView = blur
        return panel
    }

    private func filter() {
        let q = search.stringValue.trimmingCharacters(in: .whitespaces)
        shown = q.isEmpty ? all : all.filter { $0.name.localizedCaseInsensitiveContains(q) }
        grid.reloadData()
    }

    private func pin(_ app: InstalledApp) {
        panel?.close()
        Apps.setPinned(BarApp(bundleID: app.bundleID, url: app.url, running: nil, pinned: false), true)
    }

    func controlTextDidChange(_ obj: Notification) { filter() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            if let first = shown.first { pin(first) }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            panel?.close()
            return true
        default:
            return false
        }
    }

    func collectionView(_ cv: NSCollectionView, numberOfItemsInSection section: Int) -> Int { shown.count }

    func collectionView(_ cv: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = cv.makeItem(withIdentifier: AppPickerItem.id, for: indexPath) as! AppPickerItem
        let app = shown[indexPath.item]
        item.icon.image = NSWorkspace.shared.icon(forFile: app.url.path)
        item.label.stringValue = app.name
        item.view.toolTip = app.name
        return item
    }

    func collectionView(_ cv: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard let i = indexPaths.first?.item, i < shown.count else { return }
        pin(shown[i])
    }
}

// MARK: - Bar window

final class Bar {
    let screen: NSScreen
    let displayID: UInt32
    let panel: NSPanel
    let spacesStack = NSStackView()
    let appsStack = NSStackView()

    init(screen: NSScreen) {
        self.screen = screen
        self.displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0

        let f = screen.frame
        let frame = NSRect(x: f.minX + barMargin, y: f.minY + barMargin,
                           width: f.width - barMargin * 2, height: barHeight)
        panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false

        let content = BarBackground()
        for stack in [spacesStack, appsStack] {
            stack.orientation = .horizontal
            stack.spacing = 2
            stack.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(stack)
        }

        NSLayoutConstraint.activate([
            spacesStack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            spacesStack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            appsStack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            appsStack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])

        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = 18
            glass.contentView = content
            panel.contentView = glass
        } else {
            let blur = NSVisualEffectView()
            blur.material = .hudWindow
            blur.state = .active
            blur.wantsLayer = true
            blur.layer?.cornerRadius = 18
            blur.layer?.masksToBounds = true
            content.translatesAutoresizingMaskIntoConstraints = false
            blur.addSubview(content)
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
                content.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
                content.topAnchor.constraint(equalTo: blur.topAnchor),
                content.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
            ])
            panel.contentView = blur
        }
        panel.orderFrontRegardless()
    }

    func setApps(_ apps: [BarApp]) {
        appsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for app in apps {
            let tile = appTile(app)
            tile.onDragMoved = { [weak self, weak tile] event in
                if let self, let tile { self.drag(tile, to: event) }
            }
            tile.onDragEnded = { [weak self] in
                guard let self else { return }
                Order.save(visible: self.appsStack.arrangedSubviews.compactMap { ($0 as? AppTile)?.bundleID })
            }
            appsStack.addArrangedSubview(tile)
        }
    }

    /// Live reorder: slot the dragged tile in front of the first tile whose
    /// center is right of the mouse.
    private func drag(_ tile: AppTile, to event: NSEvent) {
        let x = appsStack.convert(event.locationInWindow, from: nil).x
        let others = appsStack.arrangedSubviews.filter { $0 !== tile }
        let target = others.filter { $0.frame.midX < x }.count
        guard appsStack.arrangedSubviews.firstIndex(of: tile) != target else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.allowsImplicitAnimation = true
            appsStack.removeArrangedSubview(tile)
            appsStack.insertArrangedSubview(tile, at: target)
            appsStack.layoutSubtreeIfNeeded()
        }
    }

    func setSpaces(_ spaces: [YabaiSpace]) {
        spacesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        // Numbered by yabai's global index, which is also what --focus takes
        spaces.forEach { spacesStack.addArrangedSubview(spaceTile($0, label: $0.index)) }
    }

    func close() { panel.orderOut(nil) }
}

// MARK: - App

final class Controller: NSObject, NSApplicationDelegate {
    var bars: [Bar] = []
    var usr1: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ note: Notification) {
        rebuildBars()

        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didActivateApplicationNotification] {
            ws.addObserver(self, selector: #selector(refreshApps), name: name, object: nil)
        }
        ws.addObserver(self, selector: #selector(refreshSpaces), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        // A drag on one screen's bar reorders the others too
        NotificationCenter.default.addObserver(self, selector: #selector(refreshApps), name: Order.changed, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(rebuildBars),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        // Dock pins changed (dragged in/out of the Dock)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(refreshApps),
                                                            name: NSNotification.Name("com.apple.dock.prefchanged"), object: nil)

        // yabai signals: `pkill -USR1 -x GlassBar` refreshes spaces
        signal(SIGUSR1, SIG_IGN)
        let src = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        src.setEventHandler { [weak self] in self?.refreshSpaces() }
        src.resume()
        usr1 = src
    }

    @objc func rebuildBars() {
        bars.forEach { $0.close() }
        bars = NSScreen.screens.map { Bar(screen: $0) }
        refreshApps()
        refreshSpaces()
    }

    @objc func refreshApps() {
        let apps = Apps.current()
        bars.forEach { $0.setApps(apps) }
    }

    @objc func refreshSpaces() {
        DispatchQueue.global().async {
            let spaces = Yabai.spacesByDisplay()
            DispatchQueue.main.async {
                self.bars.forEach { $0.setSpaces(spaces[$0.displayID] ?? []) }
            }
        }
    }
}

let app = NSApplication.shared
let controller = Controller()
app.delegate = controller
app.setActivationPolicy(.accessory)
app.run()
