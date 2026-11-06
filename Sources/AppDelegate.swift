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
    private var statusSeparator: NSMenuItem!
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
        // These two appear only when something is wrong; otherwise the icon and the checkmark say it all.
        statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        statusSeparator = .separator()
        menu.addItem(statusSeparator)

        hapticsOffItem = NSMenuItem(title: localized("Disable Haptics", "关闭触感"), action: #selector(toggleHapticsOff), keyEquivalent: "")
        hapticsOffItem.target = self
        menu.addItem(hapticsOffItem)
        loginItem = NSMenuItem(title: localized("Open at Login", "登录时打开"), action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(loginItem)

        menu.addItem(.separator())
        let restore = NSMenuItem(title: localized("Restore Haptics and Quit…", "恢复触感并退出…"), action: #selector(restoreAndQuit), keyEquivalent: "")
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
            if showErrors, present(loginItemFailedAlert(enabling: enabled)) == .alertFirstButtonReturn {
                SMAppService.openSystemSettingsLoginItems()
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
            present(moveToApplicationsAlert())
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

    func statusText(_ status: HapticsStatus) -> String {
        switch status {
        case .off: localized("Haptics are off", "触感已关闭")
        case .on: localized("Haptics are on", "触感已打开")
        case .failed: localized("Couldn't Turn Off Haptics", "未能关闭触感")
        case .unknown: localized("Couldn't Read Haptics State", "无法读取触感状态")
        }
    }

    func spokenStatus(_ status: HapticsStatus) -> String {
        switch status {
        case .off: localized("Trackpad haptics: off", "触控板触感：已关闭")
        case .on: localized("Trackpad haptics: on", "触控板触感：已打开")
        case .failed: localized("Trackpad haptics: couldn't turn off", "触控板触感：未能关闭")
        case .unknown: localized("Trackpad haptics: unreadable", "触控板触感：无法读取")
        }
    }

    func show(_ status: HapticsStatus, wantsOff: Bool, login: SMAppService.Status) {
        let image = status.menuBarImage
        image?.accessibilityDescription = spokenStatus(status)
        statusItem?.button?.image = image
        statusItem?.button?.toolTip = statusText(status)

        statusLine?.title = statusText(status)
        statusLine?.isHidden = !status.isProblem
        statusSeparator?.isHidden = !status.isProblem

        // Wanted off but not reading off: this item retries (see toggleHapticsOff), so it is an action, not a checkbox.
        let retries = wantsOff && status != .off
        hapticsOffItem?.title = retries
            ? localized("Retry Turning Off Haptics", "重试关闭触感")
            : localized("Disable Haptics", "关闭触感")
        hapticsOffItem?.state = wantsOff && status == .off ? .on : .off

        loginItem?.state = login == .enabled ? .on : (login == .requiresApproval ? .mixed : .off)
        loginItem?.title = login == .requiresApproval
            ? localized("Open at Login (Needs Approval)…", "登录时打开（待允许）…")
            : localized("Open at Login", "登录时打开")
    }

    @objc private func toggleHapticsOff() {
        // While haptics are wanted off but do not read off, this item is "Retry" and does not flip the choice.
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
        guard present(restoreConfirmationAlert()) == .alertFirstButtonReturn else { return }

        UserDefaults.standard.set(true, forKey: hapticsWantedKey)
        while true {
            let failures = restoreEverything()
            refreshMenu()
            if failures.isEmpty { break }
            guard present(restoreFailedAlert(failures)) == .alertFirstButtonReturn else { return }
        }
        // Reopening the app later turns haptics off again.
        UserDefaults.standard.removeObject(forKey: hapticsWantedKey)
        NSApp.terminate(nil)
    }

    private func restoreEverything() -> [String] {
        var failures: [String] = []
        if !haptics.setEnabled(true) {
            failures.append(localized("trackpad haptics", "触控板触感"))
        }
        if setLaunchAtLogin(false) {
            UserDefaults.standard.set(true, forKey: launchAtLoginConfiguredKey)
        } else {
            failures.append(localized("Open at Login", "登录时打开"))
        }
        return failures
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - Dialogs: a title, one sentence on what happens, and the buttons.

    func moveToApplicationsAlert() -> NSAlert {
        makeAlert(
            title: localized("Move to Applications", "请移到“应用程序”文件夹"),
            message: localized("Reopen it after moving.", "移动后重新打开。"),
            confirm: localized("OK", "好"),
            cancellable: false
        )
    }

    func loginItemFailedAlert(enabling: Bool) -> NSAlert {
        // Turning it off goes through here too, so the wording follows the direction.
        makeAlert(
            title: enabling
                ? localized("Couldn't Turn On Open at Login", "无法设为登录时打开")
                : localized("Couldn't Turn Off Open at Login", "无法取消登录时打开"),
            message: enabling
                ? localized("Allow Silent Light Trackpad in Login Items for this to take effect.", "在“登录项”中允许Silent Light Trackpad后生效。")
                : localized("Turn off Silent Light Trackpad in Login Items for this to take effect.", "在“登录项”中关闭Silent Light Trackpad后生效。"),
            confirm: localized("Open Login Items Settings…", "打开登录项设置…")
        )
    }

    func restoreConfirmationAlert() -> NSAlert {
        makeAlert(
            title: localized("Restore Haptics and Quit?", "恢复触感并退出？"),
            message: localized(
                "Trackpad haptics will turn back on, and Open at Login will turn off.",
                "触控板触感会恢复，“登录时打开”会关闭。"
            ),
            confirm: localized("Restore and Quit", "恢复并退出")
        )
    }

    func restoreFailedAlert(_ failures: [String]) -> NSAlert {
        makeAlert(
            title: localized("Couldn't Restore Everything", "未能全部恢复"),
            message: localized("Not restored: ", "未恢复：")
                + failures.joined(separator: localized(", ", "、")) + localized(".", "。"),
            confirm: localized("Retry", "重试")
        )
    }

    private func makeAlert(title: String, message: String, confirm: String, cancellable: Bool = true) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: confirm)
        if cancellable {
            // AppKit binds Esc only to a button titled exactly "Cancel", not to "取消".
            alert.addButton(withTitle: localized("Cancel", "取消")).keyEquivalent = "\u{1b}"
        }
        return alert
    }

    @discardableResult
    private func present(_ alert: NSAlert) -> NSApplication.ModalResponse {
        // A menu bar app is not frontmost, so without this Esc and Return can go to whichever app is.
        NSApp.activate()
        return alert.runModal()
    }
}
