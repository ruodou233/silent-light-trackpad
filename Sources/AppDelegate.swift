import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    // Left behind by versions up to 0.5.1, which still had the light-pressure click engine.
    nonisolated static let legacyPreferenceKeys = [
        "lightClickEnabled", "pressureThreshold", "originalTapToClickState", "originalTapToClick",
        "loginRegistrationIdentity", "tapOverrideActive", "restorePending",
    ]

    private let haptics = HapticsController.shared

    private var statusItem: NSStatusItem!
    private var statusLine: NSMenuItem!
    private var hapticsOffItem: NSMenuItem!
    private var loginItem: NSMenuItem!

    private let launchAtLoginConfiguredKey = "launchAtLoginEnabled"
    private let hapticsWantedKey = "hapticsWanted" // Set when the user asks for haptics back.

    private var usesChinese: Bool {
        Locale.preferredLanguages.first?.hasPrefix("zh") == true
    }

    private func localized(_ english: String, _ chinese: String) -> String {
        usesChinese ? chinese : english
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        guard requireApplicationsInstallation(), becomeOnlyInstance() else { return }
        for key in Self.legacyPreferenceKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        buildMenu()

        configureDefaultLaunchAtLoginIfNeeded()
        syncHaptics()
        installResilienceObservers()
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        DispatchQueue.main.async { [weak self] in
            self?.statusItem?.button?.performClick(nil)
        }
        return true
    }

    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.menu = makeMenu()
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())

        hapticsOffItem = NSMenuItem(title: localized("Disable haptics", "关闭触感"), action: #selector(toggleHapticsOff), keyEquivalent: "")
        hapticsOffItem.target = self
        menu.addItem(hapticsOffItem)
        loginItem = NSMenuItem(title: localized("Open at login", "登录时打开"), action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(loginItem)

        menu.addItem(.separator())
        let restore = NSMenuItem(title: localized("Restore and quit…", "还原并退出…"), action: #selector(restoreAndQuit), keyEquivalent: "")
        restore.target = self
        menu.addItem(restore)
        let quit = NSMenuItem(title: localized("Quit", "退出"), action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        syncHaptics()
    }

    private var wantsHapticsOff: Bool {
        !UserDefaults.standard.bool(forKey: hapticsWantedKey)
    }

    private func configureDefaultLaunchAtLoginIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: launchAtLoginConfiguredKey) == nil else { return }
        if setLaunchAtLogin(true) {
            defaults.set(true, forKey: launchAtLoginConfiguredKey)
        }
    }

    @discardableResult
    private func setLaunchAtLogin(_ enabled: Bool, showErrors: Bool = false) -> Bool {
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status != .enabled, service.status != .requiresApproval {
                    try service.register()
                }
            } else {
                if service.status == .enabled || service.status == .requiresApproval {
                    try service.unregister()
                }
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

    private func installResilienceObservers() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            center.addObserver(self, selector: #selector(recoverAfterSystemTransition(_:)), name: name, object: nil)
        }
    }

    @objc private func recoverAfterSystemTransition(_ notification: Notification) {
        syncHaptics()
    }

    private func syncHaptics() {
        _ = haptics.setEnabled(!wantsHapticsOff)
        refreshMenu()
    }

    private func requireApplicationsInstallation() -> Bool {
        let bundlePath = Bundle.main.bundleURL.standardizedFileURL.path
        guard bundlePath.hasPrefix("/Applications/") else {
            showAlert(
                title: localized("Move to Applications", "请移到“应用程序”文件夹"),
                message: localized(
                    "Move Silent Light Trackpad to Applications before opening it. This keeps launch at login tied to one copy.",
                    "请先把 Silent Light Trackpad 移到“应用程序”文件夹再打开，避免登录项指向不同副本。"
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

    private func refreshMenu() {
        let status = HapticsStatus(wantsOff: wantsHapticsOff, isEnabled: haptics.isEnabled)
        show(status, wantsOff: wantsHapticsOff, login: SMAppService.mainApp.status)
        // `--status` reads this instead of guessing from the command line.
        let defaults = UserDefaults.standard
        defaults.set(status.rawValue, forKey: HapticsStatus.reportedStatusKey)
        defaults.set(Int(NSRunningApplication.current.processIdentifier), forKey: HapticsStatus.reportedPIDKey)
        defaults.set(Date(), forKey: HapticsStatus.reportedAtKey)
    }

    func show(_ status: HapticsStatus, wantsOff: Bool, login: SMAppService.Status) {
        let title: String
        switch status {
        case .off: title = localized("Haptics are off", "触感已关闭")
        case .on: title = localized("Haptics are on", "触感已开启")
        case .failed: title = localized("Could not disable haptics — retry below", "触感未能关闭，点“关闭触感”重试")
        case .unknown: title = localized("Haptics state unavailable", "读不到触感状态")
        }
        statusLine?.title = title
        statusItem?.button?.image = status.menuBarImage
        statusItem?.button?.toolTip = title
        hapticsOffItem?.state = !wantsOff ? .off : (status == .off ? .on : .mixed)

        loginItem?.state = login == .enabled ? .on : (login == .requiresApproval ? .mixed : .off)
        loginItem?.title = login == .requiresApproval
            ? localized("Open at login: approval required", "登录时打开：需要批准")
            : localized("Open at login", "登录时打开")
    }

    @objc private func toggleHapticsOff() {
        // While haptics are wanted off but do not read off, the checked item retries instead of flipping.
        let retry = wantsHapticsOff && haptics.isEnabled != false
        if !retry {
            UserDefaults.standard.set(wantsHapticsOff, forKey: hapticsWantedKey)
        }
        syncHaptics()
    }

    @objc private func toggleLogin(_ sender: NSMenuItem) {
        let status = SMAppService.mainApp.status
        if status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
            return
        }
        let shouldEnable = status != .enabled
        if setLaunchAtLogin(shouldEnable, showErrors: true) {
            UserDefaults.standard.set(true, forKey: launchAtLoginConfiguredKey)
        }
        refreshMenu()
    }

    @objc private func restoreAndQuit() {
        let alert = NSAlert()
        alert.messageText = localized("Restore and quit?", "还原并退出？")
        alert.informativeText = localized(
            "This turns trackpad haptics back on, turns off Open at login, and quits the app. Tap to click is not changed.",
            "这会恢复触控板触感，关闭“登录时打开”，然后退出应用。“轻点来点按”不受影响。"
        )
        alert.addButton(withTitle: localized("Restore and quit", "还原并退出"))
        alert.addButton(withTitle: localized("Cancel", "取消"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        UserDefaults.standard.set(true, forKey: hapticsWantedKey)
        var failures: [String] = []
        if !haptics.setEnabled(true) {
            failures.append(localized("trackpad haptics", "触控板触感"))
        }
        if setLaunchAtLogin(false) {
            UserDefaults.standard.set(true, forKey: launchAtLoginConfiguredKey)
        } else {
            failures.append(localized("Open at login", "登录时打开"))
        }
        guard failures.isEmpty else {
            refreshMenu()
            showAlert(
                title: localized("Some settings could not be restored", "部分设置未能还原"),
                message: localized("Not restored: ", "未还原：") + failures.joined(separator: localized(", ", "、"))
                    + localized(". Successful items remain restored; you can retry the failed items.", "。成功项目保持还原状态，可以再次重试失败项目。")
            )
            return
        }
        refreshMenu()
        // Reopening the app later turns haptics off again.
        UserDefaults.standard.removeObject(forKey: hapticsWantedKey)
        NSApp.terminate(nil)
    }

    @objc private func quit() { NSApp.terminate(nil) }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
