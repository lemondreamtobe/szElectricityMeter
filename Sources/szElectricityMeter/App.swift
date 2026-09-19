import AppKit
import SwiftUI
import MeterCore

@main enum SzElectricityMeterApp {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--configure-stdin") && !CommandLine.arguments.contains("--demo") {
            configureFromStdin(); return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
    private struct Setup: Decodable {
        let token: String
        let areaCode: String
        let eleCustId: String
        let meteringPointId: String
    }
    private static func configureFromStdin() {
        do {
            let setup = try JSONDecoder().decode(Setup.self, from: FileHandle.standardInput.readDataToEndOfFile())
            guard !setup.token.isEmpty, !setup.token.contains(where: { $0.isWhitespace || $0 == ";" }), !setup.eleCustId.isEmpty, !setup.meteringPointId.isEmpty else { throw MeterError.configuration }
            let disk = LocalStore()
            var config = try disk.loadConfiguration()
            config.areaCode = setup.areaCode; config.customerID = setup.eleCustId; config.meteringPointID = setup.meteringPointId
            try TokenVault.save(setup.token)
            try disk.saveConfiguration(config)
            print("Configuration saved. Token stored in macOS Keychain.")
        } catch {
            FileHandle.standardError.write(Data("Configuration failed; check input and Keychain access.\n".utf8)); exit(1)
        }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = MeterStore(demo: CommandLine.arguments.contains("--demo"))
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var dashboard: NSWindow?
    private var settings: NSWindow?
    private var summaryPreview: NSWindow?
    private var menuScene: NSWindow?
    private var appearanceObservation: NSKeyValueObservation?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self; statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        appearanceObservation = statusItem.button?.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.updateStatus() }
        }
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 396, height: 648)
        popover.contentViewController = NSHostingController(rootView: PopoverView(store: store, showDashboard: { [weak self] in self?.showDashboard() }, showSettings: { [weak self] in self?.showSettings() }))
        store.onStatusChange = { [weak self] in self?.updateStatus() }
        updateStatus(); store.start()
        if !store.isConfigured { showSettings() }
        else if CommandLine.arguments.contains("--show") { showDashboard() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showDashboard(); return true
    }
    @objc private func togglePopover() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            let open = menu.addItem(withTitle: "查看用电详情", action: #selector(openDashboard), keyEquivalent: ""); open.target = self
            let settings = menu.addItem(withTitle: "设置…", action: #selector(openSettings), keyEquivalent: ","); settings.target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: "退出szElectricityMeter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            statusItem.menu = menu; statusItem.button?.performClick(nil); statusItem.menu = nil
            return
        }
        if popover.isShown { popover.performClose(nil) }
        else if let button = statusItem.button {
            store.scheduledRefresh()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    @objc private func openDashboard() { showDashboard() }
    @objc private func openSettings() { showSettings() }
    @objc private func openSummary() {
        guard store.isDemo else { togglePopover(); return }
        // A persistent demo window lets contributors inspect the real popover view
        // without transient dismissal while recording screenshots.
        if summaryPreview == nil {
            let window = makeWindow(title: "szElectricityMeter · 摘要演示", size: NSSize(width: 396, height: 670))
            window.styleMask.remove(.resizable)
            window.contentViewController = NSHostingController(rootView: PopoverView(store: store, showDashboard: { [weak self] in self?.showDashboard() }, showSettings: { [weak self] in self?.showSettings() }).frame(width: 396, height: 648))
            summaryPreview = window
        }
        summaryPreview?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func openMenuScene() {
        guard store.isDemo else { return }
        if menuScene == nil {
            let window = makeWindow(title: "szElectricityMeter · 菜单栏场景演示", size: NSSize(width: 880, height: 730))
            window.styleMask.remove(.resizable)
            window.contentViewController = NSHostingController(rootView: DemoSceneView(store: store, statusIcon: { [weak self] analysis in
                self?.ringImage(fraction: analysis.remainingFraction, time: analysis.timeRemainingFraction,
                                tier: analysis.tier, appearance: NSAppearance(named: .darkAqua)!) ?? NSImage()
            }, statusTitle: { [weak self] in self?.statusItem.button?.title ?? "" },
            showDashboard: { [weak self] in self?.showDashboard() },
            showSettings: { [weak self] in self?.showSettings() }))
            menuScene = window
        }
        menuScene?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func showDashboard() {
        popover.performClose(nil)
        if dashboard == nil {
            let window = makeWindow(title: "szElectricityMeter", size: NSSize(width: 1080, height: 850))
            window.minSize = NSSize(width: 940, height: 700)
            window.contentViewController = NSHostingController(rootView: DashboardView(store: store, showSettings: { [weak self] in self?.showSettings() }))
            if !store.isDemo { window.setFrameAutosaveName("ShenzhenMeterDashboard") }
            dashboard = window
        }
        dashboard?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func showSettings() {
        popover.performClose(nil)
        if settings == nil {
            let window = makeWindow(title: "szElectricityMeter · 设置", size: NSSize(width: 600, height: 690))
            window.styleMask.remove(.resizable)
            settings = window
        }
        if settings?.isVisible != true { settings?.contentViewController = NSHostingController(rootView: SettingsView(store: store)) }
        settings?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    private func makeWindow(title: String, size: NSSize) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = title; window.isReleasedWhenClosed = false; window.center()
        window.titlebarAppearsTransparent = true
        return window
    }
    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        let summary = appMenu.addItem(withTitle: "用电摘要", action: #selector(openSummary), keyEquivalent: "m")
        summary.keyEquivalentModifierMask = [.command, .shift]; summary.target = self
        let preferences = appMenu.addItem(withTitle: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        preferences.target = self
        if store.isDemo {
            let scene = appMenu.addItem(withTitle: "菜单栏完整场景", action: #selector(openMenuScene), keyEquivalent: "p")
            scene.keyEquivalentModifierMask = [.command, .shift]; scene.target = self
            let export = appMenu.addItem(withTitle: "导出当前演示窗口为 2× PNG", action: #selector(exportDemoWindow), keyEquivalent: "s")
            export.keyEquivalentModifierMask = [.command, .shift]; export.target = self
        }
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出szElectricityMeter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "编辑"); editItem.submenu = edit
        edit.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let windowItem = NSMenuItem(); main.addItem(windowItem)
        let windows = NSMenu(title: "窗口"); windowItem.submenu = windows
        windows.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        NSApp.mainMenu = main
    }
    @objc private func exportDemoWindow() {
        guard store.isDemo, let view = NSApp.keyWindow?.contentView else { return }
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--screenshot-directory"), args.indices.contains(index + 1) else {
            let alert = NSAlert()
            alert.messageText = "请指定演示截图目录"
            alert.informativeText = "启动演示时加上 --screenshot-directory 和输出目录路径，即可导出当前窗口的原生 2× PNG。"
            alert.runModal(); return
        }
        view.layoutSubtreeIfNeeded()
        let bounds = view.bounds
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * 2), pixelsHigh: Int(bounds.height * 2), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        bitmap.size = bounds.size
        view.cacheDisplay(in: bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
        do {
            let directory = URL(fileURLWithPath: args[index + 1], isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let name = "demo-\(Int(Date().timeIntervalSince1970 * 1000)).png"
            try png.write(to: directory.appendingPathComponent(name), options: .atomic)
        } catch {
            let alert = NSAlert(); alert.messageText = "无法保存演示截图"
            alert.informativeText = "请检查输出目录是否可写。"; alert.runModal()
        }
    }
    private func updateStatus() {
        guard let button = statusItem?.button else { return }
        let config = store.configuration
        let appearance = config.appearance == "light" ? NSAppearance(named: .aqua) : (config.appearance == "dark" ? NSAppearance(named: .darkAqua) : nil)
        if NSApp.appearance?.name != appearance?.name { NSApp.appearance = appearance }
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let stale = store.errors[store.currentMonth.key] != nil || store.current?.isDelayed() == true
        if let analysis = store.currentAnalysis {
            button.image = ringImage(fraction: analysis.remainingFraction, time: analysis.timeRemainingFraction, tier: config.tariff.mode == .combined ? 1 : analysis.tier, appearance: button.effectiveAppearance)
            if config.menuStyle == "ring" { button.title = stale || store.needsToken ? " !" : "" }
            else if config.menuStyle == "used" || analysis.remaining == nil { button.title = " \(analysis.snapshot.total.meter(1)) 度\(stale ? " !" : "")" }
            else { button.title = " 余 \(analysis.remaining!.meter(1)) 度\(stale ? " !" : "")" }
            button.toolTip = "szElectricityMeter · 本月 \(analysis.snapshot.total.meter(2)) 度\(stale ? " · 数据待更新" : "")"
        } else {
            button.image = NSImage(systemSymbolName: "bolt.circle", accessibilityDescription: "szElectricityMeter")
            button.title = store.needsToken ? " 待配置" : (store.errors[store.currentMonth.key] != nil ? " 待更新" : " …")
            button.toolTip = "szElectricityMeter"
        }
        if store.isDemo { button.title += " · 演示" }
        button.imagePosition = .imageLeading
        button.setAccessibilityLabel(button.toolTip)
    }
    private func ringImage(fraction: Double, time: Double, tier: Int, appearance: NSAppearance) -> NSImage {
        let semanticAccent: NSColor = tier == 1 ? .systemGreen : (tier == 2 ? .systemOrange : .systemRed)
        var accent = semanticAccent
        var neutral = NSColor.labelColor
        appearance.performAsCurrentDrawingAppearance {
            accent = semanticAccent.usingColorSpace(.sRGB) ?? semanticAccent
            neutral = NSColor.labelColor.usingColorSpace(.sRGB) ?? .labelColor
        }
        let image = NSImage(size: NSSize(width: 21, height: 21), flipped: false) { _ in
            for (radius, width, value, color) in [(8.5, 2.3, fraction, accent), (5.0, 1.3, time, neutral)] {
                let rect = NSRect(x: 10.5 - radius, y: 10.5 - radius, width: radius * 2, height: radius * 2)
                color.withAlphaComponent(0.22).setStroke()
                let track = NSBezierPath(ovalIn: rect); track.lineWidth = width; track.stroke()
                if value > 0 {
                    color.setStroke()
                    let path = NSBezierPath(); path.lineWidth = width; path.lineCapStyle = .round
                    path.appendArc(withCenter: NSPoint(x: 10.5, y: 10.5), radius: radius, startAngle: 90, endAngle: 90 - 360 * min(1, value), clockwise: true)
                    path.stroke()
                }
            }
            return true
        }
        // Template images are tinted monochrome by macOS, which would remove the tier color.
        image.isTemplate = false
        return image
    }
}
