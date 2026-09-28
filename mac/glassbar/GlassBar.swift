// GlassBar — a full-width Liquid Glass bar along the bottom of every screen.
//
//   left:   yabai spaces on that display (click to switch)
//   center: Dock-pinned apps + other running apps (click to open/focus)
// Clock and battery stay in the menu bar.
//
// Pinned apps are read from the Dock's own pin list, so pin/unpin by dragging
// in and out of the (auto-hidden) Dock. Built and installed by install.sh.
// yabai pokes it with SIGUSR1 (see mac/yabai/yabairc) when windows come and go.

import AppKit

let barHeight: CGFloat = 60
let barMargin: CGFloat = 8     // gap between the bar and the screen edges
let iconSize: CGFloat = 48
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
}

// MARK: - Apps

struct BarApp {
    let bundleID: String
    let url: URL
    let running: NSRunningApplication?
}

enum Apps {
    /// Bundle IDs pinned in the Dock, in Dock order.
    static func dockPins() -> [String] {
        let dock = UserDefaults(suiteName: "com.apple.dock")
        let items = dock?.array(forKey: "persistent-apps") as? [[String: Any]] ?? []
        return items.compactMap { ($0["tile-data"] as? [String: Any])?["bundle-identifier"] as? String }
    }

    static func current() -> [BarApp] {
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        var byID: [String: NSRunningApplication] = [:]
        for app in running { if let id = app.bundleIdentifier, byID[id] == nil { byID[id] = app } }

        var result: [BarApp] = []
        var seen = Set<String>()
        for id in dockPins() where !seen.contains(id) {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { continue }
            result.append(BarApp(bundleID: id, url: url, running: byID[id]))
            seen.insert(id)
        }
        for app in running {
            guard let id = app.bundleIdentifier, !seen.contains(id), let url = app.bundleURL else { continue }
            result.append(BarApp(bundleID: id, url: url, running: app))
            seen.insert(id)
        }
        return result
    }
}

// MARK: - Views

/// Invisible button that just forwards clicks; the look comes from its subviews.
final class ClickView: NSView {
    var onClick: (() -> Void)?
    var menuProvider: (() -> NSMenu?)?

    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }
    override func menu(for event: NSEvent) -> NSMenu? { menuProvider?() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

func appTile(_ app: BarApp) -> NSView {
    let tile = ClickView()
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
    tile.menuProvider = {
        guard let running = app.running else { return nil }
        let menu = NSMenu()
        let quit = MenuAction(title: "Quit") { running.terminate() }
        menu.addItem(quit.item)
        return menu
    }
    return tile
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

        let content = NSView()
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
        apps.forEach { appsStack.addArrangedSubview(appTile($0)) }
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
