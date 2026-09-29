// GlassBar — a full-width Liquid Glass bar along the bottom of every screen.
//
//   left:   yabai spaces on that display (click to switch)
//   center: Dock-pinned apps + other running apps (click to open/focus)
//   right:  system stat cards (CPU, memory, GPU, temps, disk), coloured
//           green / yellow / red against per-stat thresholds
// Clock and battery stay in the menu bar.
//
// Pinned apps are read from the Dock's own pin list, so pin/unpin by dragging
// in and out of the (auto-hidden) Dock. Drag icons within the bar to reorder
// them; that order is saved in GlassBar's own defaults and survives restarts. Built and installed by install.sh.
// yabai pokes it with SIGUSR1 (see mac/yabai/yabairc) when windows come and go.

import AppKit
import IOKit

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

// MARK: - System stats

/// One reading of everything the stat cards show. nil hides that card
/// (e.g. no temperature sensors on an Intel Mac).
struct StatSample {
    var cpu: Double?       // percent busy, all cores
    var mem: Double?       // percent used, Activity Monitor's "Memory Used"
    var memDetail = ""
    var gpu: Double?       // percent, IOAccelerator's "Device Utilization %"
    var cpuTemp: Double?   // °C
    var gpuTemp: Double?   // °C
    var disk: Double?      // percent used on the boot volume
    var diskDetail = ""
}

/// Samples CPU, memory, GPU, temperatures and disk. Not thread-safe; the
/// controller calls it from one serial queue.
final class StatSampler {
    private var lastBusy: UInt64 = 0
    private var lastTotal: UInt64 = 0
    private let sensors = TempSensors()

    func sample() -> StatSample {
        var s = StatSample()
        s.cpu = cpu()
        (s.mem, s.memDetail) = memory()
        s.gpu = gpu()
        (s.cpuTemp, s.gpuTemp) = sensors.read()
        (s.disk, s.diskDetail) = disk()
        return s
    }

    /// Busy share since the previous call, from per-core tick counters.
    private func cpu() -> Double? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                  &cpuCount, &info, &infoCount) == KERN_SUCCESS,
              let info
        else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }

        var busy: UInt64 = 0, total: UInt64 = 0
        for i in 0..<Int(cpuCount) {
            let base = Int(CPU_STATE_MAX) * i
            func ticks(_ state: Int32) -> UInt64 { UInt64(UInt32(bitPattern: info[base + Int(state)])) }
            let used = ticks(CPU_STATE_USER) + ticks(CPU_STATE_SYSTEM) + ticks(CPU_STATE_NICE)
            busy += used
            total += used + ticks(CPU_STATE_IDLE)
        }
        defer { lastBusy = busy; lastTotal = total }
        // First call has no baseline; counters going backwards would underflow
        guard lastTotal > 0, total > lastTotal, busy >= lastBusy else { return nil }
        return Double(busy - lastBusy) / Double(total - lastTotal) * 100
    }

    /// App memory + wired + compressed, the same sum as Activity Monitor.
    private func memory() -> (Double?, String) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (nil, "") }
        let page = UInt64(vm_kernel_page_size)
        let app = UInt64(stats.internal_page_count) - UInt64(min(stats.purgeable_count, stats.internal_page_count))
        let used = (app + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
        let total = ProcessInfo.processInfo.physicalMemory
        return (Double(used) / Double(total) * 100, "Memory: \(gb(used)) of \(gb(total))")
    }

    /// Busiest GPU's utilisation. Readable without root on Apple Silicon.
    private func gpu() -> Double? {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iter) == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(iter) }

        var best: Double?
        var service = IOIteratorNext(iter)
        while service != 0 {
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = props?.takeRetainedValue() as? [String: Any],
               let perf = dict["PerformanceStatistics"] as? [String: Any],
               let util = perf["Device Utilization %"] as? NSNumber {
                best = max(best ?? 0, util.doubleValue)
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iter)
        }
        return best
    }

    private func disk() -> (Double?, String) {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let total = v.volumeTotalCapacity, total > 0,
              let free = v.volumeAvailableCapacityForImportantUsage
        else { return (nil, "") }
        let used = UInt64(total) - UInt64(min(max(free, 0), Int64(total)))
        return (Double(used) / Double(total) * 100, "Disk: \(gb(used)) of \(gb(UInt64(total)))")
    }

    private func gb(_ bytes: UInt64) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_073_741_824)
    }
}

/// CPU and GPU die temperatures from the Apple Silicon sensor hub.
///
/// There is no public API for these. This is the IOHIDEventSystemClient
/// route the Stats app uses, which needs no root. The functions are private,
/// so they are looked up at runtime: if a macOS update removes or renames
/// them, the temperature cards just hide instead of GlassBar failing to
/// build or crashing. Sensor names vary by chip ("PMU tdie*" for CPU dies,
/// "GPU MTR Temp Sensor*" for the GPU), hence the loose name matching.
final class TempSensors {
    private typealias CreateFn = @convention(c) (UnsafeRawPointer?) -> UnsafeMutableRawPointer?   // allocator
    private typealias SetMatchingFn = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer) -> Int32
    private typealias CopyServicesFn = @convention(c) (UnsafeMutableRawPointer) -> UnsafeRawPointer?
    private typealias CopyPropertyFn = @convention(c) (UnsafeRawPointer, UnsafeRawPointer) -> UnsafeRawPointer?
    private typealias CopyEventFn = @convention(c) (UnsafeRawPointer, Int64, Int32, Int64) -> UnsafeRawPointer?
    private typealias GetFloatFn = @convention(c) (UnsafeRawPointer, Int32) -> Double

    private static let temperatureEvent: Int64 = 15   // kIOHIDEventTypeTemperature
    private static let temperatureField = Int32(15 << 16)

    private var copyProperty: CopyPropertyFn?
    private var copyEvent: CopyEventFn?
    private var getFloat: GetFloatFn?
    private var cpuServices: [UnsafeRawPointer] = []
    private var gpuServices: [UnsafeRawPointer] = []
    private var client: UnsafeMutableRawPointer?   // owns the services below
    private var servicesArray: CFArray?            // keeps the service refs alive

    init() {
        guard let iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW) else { return }
        func load<T>(_ name: String, as _: T.Type) -> T? {
            dlsym(iokit, name).map { unsafeBitCast($0, to: T.self) }
        }
        guard let create = load("IOHIDEventSystemClientCreate", as: CreateFn.self),
              let setMatching = load("IOHIDEventSystemClientSetMatching", as: SetMatchingFn.self),
              let copyServices = load("IOHIDEventSystemClientCopyServices", as: CopyServicesFn.self),
              let copyProperty = load("IOHIDServiceClientCopyProperty", as: CopyPropertyFn.self),
              let copyEvent = load("IOHIDServiceClientCopyEvent", as: CopyEventFn.self),
              let getFloat = load("IOHIDEventGetFloatValue", as: GetFloatFn.self),
              let client = create(nil)   // nil = default allocator
        else { return }
        self.client = client
        self.copyProperty = copyProperty
        self.copyEvent = copyEvent
        self.getFloat = getFloat

        // Vendor page 0xff00, usage 5: the temperature sensors
        let matching = ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary
        _ = setMatching(client, Unmanaged.passUnretained(matching).toOpaque())
        guard let raw = copyServices(client) else { return }
        let services = Unmanaged<CFArray>.fromOpaque(raw).takeRetainedValue()
        servicesArray = services

        for i in 0..<CFArrayGetCount(services) {
            guard let service = CFArrayGetValueAtIndex(services, i),
                  let nameRaw = copyProperty(service, Unmanaged.passUnretained("Product" as CFString).toOpaque())
            else { continue }
            let name = (Unmanaged<CFString>.fromOpaque(nameRaw).takeRetainedValue() as String).lowercased()
            if name.contains("gpu") {
                gpuServices.append(service)
            } else if name.contains("tdie") || name.contains("pacc") || name.contains("eacc") || name.contains("cpu") {
                cpuServices.append(service)
            }
        }
    }

    /// Average of each group's sensors, ignoring junk readings.
    func read() -> (cpu: Double?, gpu: Double?) {
        (average(cpuServices), average(gpuServices))
    }

    private func average(_ services: [UnsafeRawPointer]) -> Double? {
        guard let copyEvent, let getFloat else { return nil }
        var sum = 0.0, n = 0.0
        for service in services {
            guard let event = copyEvent(service, Self.temperatureEvent, 0, 0) else { continue }
            let value = getFloat(event, Self.temperatureField)
            Unmanaged<AnyObject>.fromOpaque(event).release()
            if value > 0 && value < 150 { sum += value; n += 1 }
        }
        return n > 0 ? sum / n : nil
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

/// A small scorecard: title over icon + value, the value tinted by how
/// worrying it is. Mirrors the stat cards on the Arch dock.
final class StatCard: NSView {
    let warn: Double
    let crit: Double
    private let valueLabel = NSTextField(labelWithString: "–")

    init(title: String, symbol: String, warn: Double, crit: Double) {
        self.warn = warn
        self.crit = crit
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.06).cgColor
        translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: title.uppercased())
        titleLabel.font = .systemFont(ofSize: 9, weight: .semibold)
        titleLabel.textColor = .tertiaryLabelColor

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .medium))
        icon.contentTintColor = .secondaryLabelColor

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .bold)

        let row = NSStackView(views: [icon, valueLabel])
        row.orientation = .horizontal
        row.spacing = 5
        let column = NSStackView(views: [titleLabel, row])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 2
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 48),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 76),
            widthAnchor.constraint(greaterThanOrEqualTo: column.widthAnchor, constant: 24),
            column.centerXAnchor.constraint(equalTo: centerXAnchor),
            column.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    /// nil hides the card (no reading available on this Mac).
    func show(_ value: Double?, format: String, detail: String = "") {
        isHidden = value == nil
        guard let value else { return }
        valueLabel.stringValue = String(format: format, value)
        valueLabel.textColor = value >= crit ? .systemRed : value >= warn ? .systemYellow : .systemGreen
        toolTip = detail.isEmpty ? nil : detail
    }
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
    let statsStack = NSStackView()
    // Same thresholds as the Arch dock (quickshell/dock/Dock.qml)
    let cpuCard = StatCard(title: "CPU", symbol: "cpu", warn: 50, crit: 80)
    let memCard = StatCard(title: "Mem", symbol: "memorychip", warn: 60, crit: 85)
    let gpuCard = StatCard(title: "GPU", symbol: "square.3.layers.3d", warn: 60, crit: 90)
    let cpuTempCard = StatCard(title: "CPU temp", symbol: "thermometer.medium", warn: 70, crit: 85)
    let gpuTempCard = StatCard(title: "GPU temp", symbol: "thermometer.medium", warn: 70, crit: 83)
    let diskCard = StatCard(title: "Disk", symbol: "internaldrive", warn: 75, crit: 90)

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
        for stack in [spacesStack, appsStack, statsStack] {
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
            statsStack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            statsStack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])
        statsStack.spacing = 6
        for card in [cpuCard, memCard, gpuCard, cpuTempCard, gpuTempCard, diskCard] {
            card.isHidden = true   // until the first sample
            statsStack.addArrangedSubview(card)
        }

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

    func setStats(_ s: StatSample) {
        cpuCard.show(s.cpu, format: "%.0f%%")
        memCard.show(s.mem, format: "%.0f%%", detail: s.memDetail)
        gpuCard.show(s.gpu, format: "%.0f%%")
        cpuTempCard.show(s.cpuTemp, format: "%.0f°C")
        gpuTempCard.show(s.gpuTemp, format: "%.0f°C")
        diskCard.show(s.disk, format: "%.0f%%", detail: s.diskDetail)
    }

    func close() { panel.orderOut(nil) }
}

// MARK: - App

final class Controller: NSObject, NSApplicationDelegate {
    var bars: [Bar] = []
    var usr1: DispatchSourceSignal?
    var lastStats: StatSample?
    let sampler = StatSampler()
    let statsQueue = DispatchQueue(label: "glassbar.stats")
    var statsTimer: Timer?

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

        // Stat cards: sample every 2s off the main thread
        refreshStats()
        statsTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refreshStats()
        }
    }

    func refreshStats() {
        statsQueue.async { [weak self] in
            guard let self else { return }
            let s = self.sampler.sample()
            DispatchQueue.main.async {
                self.lastStats = s
                self.bars.forEach { $0.setStats(s) }
            }
        }
    }

    @objc func rebuildBars() {
        bars.forEach { $0.close() }
        bars = NSScreen.screens.map { Bar(screen: $0) }
        refreshApps()
        refreshSpaces()
        if let lastStats { bars.forEach { $0.setStats(lastStats) } }
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
