import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // Left behind by versions up to 0.5.1, which still had the light-pressure click engine.
    nonisolated static let legacyPreferenceKeys = [
        "lightClickEnabled", "pressureThreshold", "originalTapToClickState", "originalTapToClick",
        "loginRegistrationIdentity", "tapOverrideActive",
    ]

    private let haptics = HapticsController.shared

    private var statusItem: NSStatusItem!
    private var hapticsItem: NSMenuItem!
    private var loginItem: NSMenuItem!

    private let launchAtLoginConfiguredKey = "launchAtLoginEnabled"
    private let restorePendingKey = "restorePending"

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
        if !isRestorePending {
            _ = haptics.setEnabled(false)
        }
        refreshMenu()
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
        statusItem.button?.image = NSImage(systemSymbolName: "hand.tap", accessibilityDescription: "Silent Light Trackpad")

        let menu = NSMenu()
        let title = NSMenuItem(title: "Silent Light Trackpad", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)

        hapticsItem = NSMenuItem(title: localized("Haptics: checking", "触感：检查中"), action: nil, keyEquivalent: "")
        hapticsItem.isEnabled = false
        menu.addItem(hapticsItem)
        menu.addItem(.separator())

        loginItem = NSMenuItem(title: localized("Launch at login", "登录时自动启动"), action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(loginItem)

        menu.addItem(.separator())
        let restore = NSMenuItem(title: localized("Restore everything and quit…", "一切还原并退出…"), action: #selector(restoreEverythingAndQuit), keyEquivalent: "")
        restore.target = self
        menu.addItem(restore)
        let quit = NSMenuItem(title: localized("Quit (keep settings)", "退出（保留当前设置）"), action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        refreshMenu()
    }

    private var isRestorePending: Bool {
        UserDefaults.standard.bool(forKey: restorePendingKey)
    }

    private func configureDefaultLaunchAtLoginIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: launchAtLoginConfiguredKey) == nil else {
            refreshLoginItem()
            return
        }
        if setLaunchAtLogin(true) {
            defaults.set(true, forKey: launchAtLoginConfiguredKey)
        }
        refreshLoginItem()
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

    private func refreshLoginItem() {
        guard loginItem != nil else { return }
        let status = SMAppService.mainApp.status
        loginItem.state = status == .enabled ? .on : (status == .requiresApproval ? .mixed : .off)
        if status == .requiresApproval {
            loginItem.title = localized("Launch at login: approval required", "登录时自动启动：需要批准")
        } else {
            loginItem.title = localized("Launch at login", "登录时自动启动")
        }
    }

    private func installResilienceObservers() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            center.addObserver(self, selector: #selector(recoverAfterSystemTransition(_:)), name: name, object: nil)
        }
    }

    @objc private func recoverAfterSystemTransition(_ notification: Notification) {
        guard !isRestorePending else {
            refreshMenu()
            return
        }
        _ = haptics.setEnabled(false)
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
        hapticsItem?.title = haptics.isEnabled == false
            ? localized("Haptics: fully disabled", "触感：已彻底关闭")
            : localized("Haptics: still enabled", "触感：未关闭")
        hapticsItem?.state = haptics.isEnabled == false ? .on : .off
        refreshLoginItem()
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
        refreshLoginItem()
    }

    @objc private func restoreEverythingAndQuit() {
        let alert = NSAlert()
        alert.messageText = localized("Restore all system settings?", "还原全部系统设置？")
        alert.informativeText = localized(
            "This restores trackpad haptics, disables launch at login, and quits the app. Tap to click is not changed.",
            "这会恢复触控板触感，关闭登录自启，然后退出应用。“轻点来点按”不受影响。"
        )
        alert.addButton(withTitle: localized("Restore and quit", "还原并退出"))
        alert.addButton(withTitle: localized("Cancel", "取消"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        UserDefaults.standard.set(true, forKey: restorePendingKey)
        var failures: [String] = []
        if !haptics.setEnabled(true) {
            failures.append(localized("trackpad haptics", "触控板触感"))
        }
        if setLaunchAtLogin(false) {
            UserDefaults.standard.set(true, forKey: launchAtLoginConfiguredKey)
        } else {
            failures.append(localized("launch at login", "登录自启"))
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
        UserDefaults.standard.removeObject(forKey: restorePendingKey)
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
