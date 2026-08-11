import AppKit
import ApplicationServices
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let engine = LightClickEngine.shared
    private let haptics = HapticsController.shared

    private var statusItem: NSStatusItem!
    private var pressureItem: NSMenuItem!
    private var enabledItem: NSMenuItem!
    private var hapticsItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var thresholdItems: [NSMenuItem] = []
    private var workspaceObservers: [NSObjectProtocol] = []

    private let tapOverrideActiveKey = "tapOverrideActive"
    private let originalTapToClickKey = "originalTapToClick"
    private let launchAtLoginKey = "launchAtLoginEnabled"
    private let lightClickKey = "lightClickEnabled"
    private let loginRegistrationIdentityKey = "loginRegistrationIdentity"

    private var usesChinese: Bool {
        Locale.preferredLanguages.first?.hasPrefix("zh") == true
    }

    private func localized(_ english: String, _ chinese: String) -> String {
        usesChinese ? chinese : english
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        guard requireApplicationsInstallation(), becomeOnlyInstance() else { return }
        buildMenu()
        configureCallbacks()

        syncLaunchAtLogin()
        requestAccessibilityIfNeeded()
        startConfiguredServices(showErrors: true)
        installResilienceObservers()
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.stop()
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
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

        hapticsItem = NSMenuItem(title: localized("Haptics: checking", "触感：检查中"), action: nil, keyEquivalent: "")
        hapticsItem.isEnabled = false
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

        loginItem = NSMenuItem(title: localized("Launch at login", "登录时自动启动"), action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(loginItem)

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

    private var wantsLaunchAtLogin: Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: launchAtLoginKey) == nil {
            defaults.set(true, forKey: launchAtLoginKey)
            return true
        }
        return defaults.bool(forKey: launchAtLoginKey)
    }

    private var wantsLightClick: Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: lightClickKey) == nil {
            defaults.set(true, forKey: lightClickKey)
            return true
        }
        return defaults.bool(forKey: lightClickKey)
    }

    private var loginRegistrationIdentity: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        return Bundle.main.bundleURL.standardizedFileURL.path + "|" + version
    }

    private func syncLaunchAtLogin(showErrors: Bool = false) {
        _ = setLaunchAtLogin(wantsLaunchAtLogin, showErrors: showErrors)
        refreshLoginItem()
    }

    @discardableResult
    private func setLaunchAtLogin(_ enabled: Bool, showErrors: Bool = false) -> Bool {
        let service = SMAppService.mainApp
        do {
            if enabled {
                let savedIdentity = UserDefaults.standard.string(forKey: loginRegistrationIdentityKey)
                if service.status == .enabled, savedIdentity == loginRegistrationIdentity {
                    return true
                }
                if service.status == .requiresApproval {
                    return true
                }
                if service.status == .enabled {
                    try service.unregister()
                }
                try service.register()
                UserDefaults.standard.set(loginRegistrationIdentity, forKey: loginRegistrationIdentityKey)
            } else {
                if service.status == .enabled || service.status == .requiresApproval {
                    try service.unregister()
                }
                UserDefaults.standard.removeObject(forKey: loginRegistrationIdentityKey)
            }
            return true
        } catch {
            if showErrors {
                showAlert(
                    title: localized("Launch at login needs attention", "登录自启需要处理"),
                    message: localized(
                        "Enable Silent Light Trackpad in System Settings → General → Login Items.",
                        "请在“系统设置 → 通用 → 登录项”中允许 Silent Light Trackpad。"
                    )
                )
            }
            return false
        }
    }

    private func refreshLoginItem() {
        guard loginItem != nil else { return }
        let status = SMAppService.mainApp.status
        loginItem.state = status == .enabled ? .on : (wantsLaunchAtLogin ? .mixed : .off)
        if status == .requiresApproval {
            loginItem.title = localized("Launch at login: approval required", "登录时自动启动：需要批准")
        } else {
            loginItem.title = localized("Launch at login", "登录时自动启动")
        }
    }

    private func startConfiguredServices(showErrors: Bool) {
        guard applyHapticsOff() else {
            if showErrors {
                showAlert(
                    title: localized("Could not disable haptics", "无法关闭触感"),
                    message: localized("No click settings were changed. Try reopening the app.", "点击设置未被更改，请尝试重新打开应用。")
                )
            }
            return
        }
        guard wantsLightClick else {
            refreshMenu()
            return
        }
        guard engine.start() else {
            if showErrors { showPermissionHelp() }
            return
        }
        guard temporarilyDisableSystemTapToClick() else {
            engine.stop()
            if showErrors {
                showAlert(
                    title: localized("Could not prepare Tap to click", "无法调整“轻点来点按”"),
                    message: localized("Light-pressure click could not start. Haptics remain disabled.", "轻压点击无法启动，触感仍保持关闭。")
                )
            }
            return
        }
        refreshMenu()
    }

    private func installResilienceObservers() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.recoverAfterSystemTransition() }
            }
            workspaceObservers.append(observer)
        }
    }

    private func recoverAfterSystemTransition() {
        if engine.isRunning {
            engine.stop()
        }
        if wantsLightClick, !engine.isRunning, AXIsProcessTrusted() {
            startConfiguredServices(showErrors: false)
        } else if haptics.isEnabled != false {
            _ = applyHapticsOff()
        }
        refreshMenu()
    }

    private func requireApplicationsInstallation() -> Bool {
        let bundlePath = Bundle.main.bundleURL.standardizedFileURL.path
        guard bundlePath.hasPrefix("/Applications/") else {
            showAlert(
                title: localized("Move to Applications", "请移到“应用程序”文件夹"),
                message: localized(
                    "Move Silent Light Trackpad to Applications before opening it. This keeps launch at login and Accessibility permission tied to one copy.",
                    "请先把 Silent Light Trackpad 移到“应用程序”文件夹再打开，避免登录项和辅助功能权限指向不同副本。"
                )
            )
            NSApp.terminate(nil)
            return false
        }
        return true
    }

    private func becomeOnlyInstance() -> Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return true }
        let currentPID = NSRunningApplication.current.processIdentifier
        guard let existing = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .first(where: { $0.processIdentifier != currentPID }) else { return true }
        existing.activate()
        NSApp.terminate(nil)
        return false
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
            // A missing key means the system default (Tap to click off).
            guard task.terminationStatus == 0 else { return false }
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
        if wantsLightClick {
            enabledItem?.state = engine.isRunning ? .on : .mixed
            enabledItem?.title = engine.isRunning
                ? localized("Light-pressure click", "轻压点击")
                : localized("Light-pressure click: Accessibility required", "轻压点击：需要辅助功能权限")
        } else {
            enabledItem?.state = .off
            enabledItem?.title = localized("Light-pressure click", "轻压点击")
        }
        hapticsItem?.title = haptics.isEnabled == false
            ? localized("Haptics: fully disabled", "触感：已彻底关闭")
            : localized("Haptics: still enabled", "触感：未关闭")
        hapticsItem?.state = haptics.isEnabled == false ? .on : .off
        for item in thresholdItems { item.state = item.tag == Int(engine.threshold) ? .on : .off }
        refreshLoginItem()
    }

    @objc private func toggleEnabled() {
        let shouldEnable = !wantsLightClick
        if !shouldEnable {
            engine.stop()
            guard restoreSystemTapToClick() else {
                if AXIsProcessTrusted() { startConfiguredServices(showErrors: false) }
                showAlert(
                    title: localized("Could not restore Tap to click", "无法恢复“轻点来点按”"),
                    message: localized("Light-pressure click remains enabled. Try again.", "轻压点击仍保持开启，请重试。")
                )
                refreshMenu()
                return
            }
            UserDefaults.standard.set(false, forKey: lightClickKey)
        } else {
            UserDefaults.standard.set(true, forKey: lightClickKey)
            startConfiguredServices(showErrors: true)
        }
        refreshMenu()
    }

    @objc private func selectThreshold(_ sender: NSMenuItem) {
        engine.threshold = Float(sender.tag)
        refreshMenu()
    }

    @objc private func toggleLogin(_ sender: NSMenuItem) {
        let status = SMAppService.mainApp.status
        let isRegistered = status == .enabled || status == .requiresApproval
        let shouldEnable = !isRegistered
        if setLaunchAtLogin(shouldEnable, showErrors: true) {
            UserDefaults.standard.set(shouldEnable, forKey: launchAtLoginKey)
        }
        refreshLoginItem()
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
        if !setLaunchAtLogin(false) {
            failures.append(localized("launch at login", "登录自启"))
        }
        guard failures.isEmpty else {
            _ = setLaunchAtLogin(wantsLaunchAtLogin)
            startConfiguredServices(showErrors: false)
            showAlert(
                title: localized("Some settings could not be restored", "部分设置未能还原"),
                message: localized("Not restored: ", "未还原：") + failures.joined(separator: localized(", ", "、"))
                    + localized(". The saved restore data was kept; you can try again.", "。恢复依据已保留，可以再次尝试。")
            )
            return
        }
        UserDefaults.standard.removeObject(forKey: "pressureThreshold")
        UserDefaults.standard.removeObject(forKey: lightClickKey)
        UserDefaults.standard.removeObject(forKey: loginRegistrationIdentityKey)
        UserDefaults.standard.set(false, forKey: launchAtLoginKey)
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
