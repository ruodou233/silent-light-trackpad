import AppKit
import ApplicationServices
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let engine = LightClickEngine.shared
    private let haptics = HapticsController.shared
    private let previewMode = CommandLine.arguments.contains("--preview-menu")

    private var statusItem: NSStatusItem!
    private var pressureItem: NSMenuItem!
    private var enabledItem: NSMenuItem!
    private var hapticsItem: NSMenuItem!
    private var thresholdItems: [NSMenuItem] = []
    private var wakeObserver: NSObjectProtocol?

    private let tapOverrideActiveKey = "tapOverrideActive"
    private let originalTapToClickKey = "originalTapToClick"

    private var usesChinese: Bool {
        Locale.preferredLanguages.first?.hasPrefix("zh") == true
    }

    private func localized(_ english: String, _ chinese: String) -> String {
        usesChinese ? chinese : english
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildMenu()
        configureCallbacks()

        if previewMode {
            enabledItem.state = .on
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.statusItem.button?.performClick(nil)
            }
            return
        }

        requestAccessibilityIfNeeded()
        guard engine.start() else {
            showPermissionHelp()
            return
        }
        guard temporarilyDisableSystemTapToClick() else {
            engine.stop()
            showAlert(
                title: localized("Could not prepare Tap to click", "无法调整“轻点来点按”"),
                message: localized("No system settings were changed. Try reopening the app.", "系统设置未被更改，请尝试重新打开应用。")
            )
            return
        }
        guard applyHapticsOff() else {
            _ = restoreSystemTapToClick()
            engine.stop()
            showAlert(
                title: localized("Could not disable haptics", "无法关闭触感"),
                message: localized("The click engine was stopped and Tap to click was restored.", "轻压点击已停止，“轻点来点按”已恢复。")
            )
            return
        }

        if CommandLine.arguments.contains("--show") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.statusItem.button?.performClick(nil)
            }
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                if self?.applyHapticsOff() == false {
                    self?.showAlert(
                        title: self?.localized("Could not disable haptics after wake", "唤醒后无法关闭触感") ?? "Silent Light Trackpad",
                        message: self?.localized("Use the menu to retry or restore all settings.", "请用菜单重试，或还原全部设置。") ?? ""
                    )
                }
                if self?.engine.start() == false { self?.showPermissionHelp() }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard !previewMode else { return }
        engine.stop()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusItem.button?.performClick(nil)
        return true
    }

    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "hand.tap", accessibilityDescription: "Silent Light Trackpad")

        let menu = NSMenu()
        let title = NSMenuItem(title: "Silent Light Trackpad", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)

        enabledItem = NSMenuItem(title: localized("Light-pressure click", "轻压点击"), action: #selector(toggleEnabled), keyEquivalent: "")
        enabledItem.target = self
        menu.addItem(enabledItem)

        hapticsItem = NSMenuItem(title: localized("Haptics: checking", "触感：检查中"), action: #selector(toggleHaptics), keyEquivalent: "")
        hapticsItem.target = self
        menu.addItem(hapticsItem)

        pressureItem = NSMenuItem(title: localized("Current pressure: 0 g", "当前压力：0 g"), action: nil, keyEquivalent: "")
        pressureItem.isEnabled = false
        menu.addItem(pressureItem)
        menu.addItem(.separator())

        let sensitivity = NSMenuItem(title: localized("Sensitivity", "灵敏度"), action: nil, keyEquivalent: "")
        sensitivity.isEnabled = false
        menu.addItem(sensitivity)
        let presets = usesChinese
            ? [("轻 · 40 g", 40), ("默认 · 50 g", 50), ("稳妥 · 60 g", 60), ("防误触 · 80 g", 80)]
            : [("Light · 40 g", 40), ("Default · 50 g", 50), ("Steady · 60 g", 60), ("Guarded · 80 g", 80)]
        for (title, value) in presets {
            let item = NSMenuItem(title: title, action: #selector(selectThreshold(_:)), keyEquivalent: "")
            item.target = self
            item.tag = value
            item.indentationLevel = 1
            thresholdItems.append(item)
            menu.addItem(item)
        }

        let login = NSMenuItem(title: localized("Launch at login", "登录时自动启动"), action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        let permission = NSMenuItem(title: localized("Open Accessibility Settings…", "打开辅助功能设置…"), action: #selector(openAccessibility), keyEquivalent: "")
        permission.target = self
        menu.addItem(permission)
        let restore = NSMenuItem(title: localized("Restore everything and quit…", "一切还原并退出…"), action: #selector(restoreEverythingAndQuit), keyEquivalent: "")
        restore.target = self
        menu.addItem(restore)
        let quit = NSMenuItem(title: localized("Quit (keep settings)", "退出（保留当前设置）"), action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        refreshMenu()
    }

    private func configureCallbacks() {
        engine.onPressureChange = { [weak self] pressure in
            let format = self?.localized("Current pressure: %.0f g", "当前压力：%.0f g") ?? "%.0f g"
            self?.pressureItem.title = String(format: format, pressure)
        }
        engine.onStateChange = { [weak self] _ in self?.refreshMenu() }
    }

    private func requestAccessibilityIfNeeded() {
        guard !AXIsProcessTrusted() else { return }
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    @discardableResult
    private func applyHapticsOff() -> Bool {
        let success = haptics.setEnabled(false)
        refreshMenu()
        return success
    }

    private func temporarilyDisableSystemTapToClick() -> Bool {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: tapOverrideActiveKey) {
            return writeSystemTapToClick(false)
        }

        guard let original = readSystemTapToClick() else { return false }
        if original, !writeSystemTapToClick(false) { return false }
        defaults.set(original, forKey: originalTapToClickKey)
        defaults.set(true, forKey: tapOverrideActiveKey)
        return true
    }

    private func restoreSystemTapToClick() -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: tapOverrideActiveKey) else { return true }
        guard writeSystemTapToClick(defaults.bool(forKey: originalTapToClickKey)) else { return false }
        defaults.removeObject(forKey: tapOverrideActiveKey)
        defaults.removeObject(forKey: originalTapToClickKey)
        return true
    }

    private func readSystemTapToClick() -> Bool? {
        let task = Process()
        let output = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        task.arguments = ["read", "com.apple.AppleMultitouchTrackpad", "Clicking"]
        task.standardOutput = output
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else { return nil }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let value = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return value == "1" || value.lowercased() == "true"
        } catch {
            return nil
        }
    }

    private func writeSystemTapToClick(_ enabled: Bool) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        task.arguments = ["write", "com.apple.AppleMultitouchTrackpad", "Clicking", "-bool", enabled ? "true" : "false"]
        do {
            try task.run()
        } catch {
            return false
        }
        task.waitUntilExit()
        return task.terminationStatus == 0 && readSystemTapToClick() == enabled
    }

    private func refreshMenu() {
        enabledItem?.state = engineState ? .on : .off
        hapticsItem?.title = haptics.isEnabled == false
            ? localized("Haptics: fully disabled", "触感：已彻底关闭")
            : localized("Haptics: still enabled", "触感：未关闭")
        hapticsItem?.state = haptics.isEnabled == false ? .on : .off
        for item in thresholdItems { item.state = item.tag == Int(engine.threshold) ? .on : .off }
    }

    private var engineState: Bool { engine.isRunning }

    @objc private func toggleEnabled() {
        if enabledItem.state == .on {
            engine.stop()
        } else if !engine.start() {
            showPermissionHelp()
        }
        refreshMenu()
    }

    @objc private func toggleHaptics() {
        let shouldEnable = haptics.isEnabled == false
        _ = haptics.setEnabled(shouldEnable)
        refreshMenu()
    }

    @objc private func selectThreshold(_ sender: NSMenuItem) {
        engine.threshold = Float(sender.tag)
        refreshMenu()
    }

    @objc private func toggleLogin(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
                sender.state = .off
            } else {
                try SMAppService.mainApp.register()
                sender.state = .on
            }
        } catch {
            showAlert(title: localized("Could not change login item", "无法更改启动项"), message: error.localizedDescription)
        }
    }

    @objc private func openAccessibility() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    @objc private func restoreEverythingAndQuit() {
        let alert = NSAlert()
        alert.messageText = localized("Restore all system settings?", "还原全部系统设置？")
        alert.informativeText = localized(
            "This restores trackpad haptics and your original Tap to click setting, disables launch at login, resets the pressure preset, and quits the app.",
            "这会恢复触控板触感和原来的“轻点来点按”，关闭登录自启，重置力度选项，然后退出应用。"
        )
        alert.addButton(withTitle: localized("Restore and quit", "还原并退出"))
        alert.addButton(withTitle: localized("Cancel", "取消"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        engine.stop()
        var failures: [String] = []
        if !haptics.setEnabled(true) {
            failures.append(localized("trackpad haptics", "触控板触感"))
        }
        if !restoreSystemTapToClick() {
            failures.append(localized("Tap to click", "轻点来点按"))
        }
        if SMAppService.mainApp.status == .enabled {
            do {
                try SMAppService.mainApp.unregister()
            } catch {
                failures.append(localized("launch at login", "登录自启"))
            }
        }
        guard failures.isEmpty else {
            showAlert(
                title: localized("Some settings could not be restored", "部分设置未能还原"),
                message: localized("Not restored: ", "未还原：") + failures.joined(separator: localized(", ", "、"))
                    + localized(". The saved restore data was kept; you can try again.", "。恢复依据已保留，可以再次尝试。")
            )
            return
        }
        UserDefaults.standard.removeObject(forKey: "pressureThreshold")
        NSApp.terminate(nil)
    }

    @objc private func quit() { NSApp.terminate(nil) }

    private func showPermissionHelp() {
        showAlert(
            title: localized("Accessibility permission required", "需要辅助功能权限"),
            message: localized(
                "Allow Silent Light Trackpad to control clicks, then quit and reopen the app.",
                "请允许 Silent Light Trackpad 控制点击，然后关闭并重新打开应用。"
            )
        )
        openAccessibility()
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
