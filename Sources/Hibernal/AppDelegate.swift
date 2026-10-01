import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let loginLaunch: Bool

    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var hotKeyManager: HotKeyManager?
    private var settingsWindow: NSWindow?
    private var settingsObserver: NSObjectProtocol?
    private var showSettingsObserver: NSObjectProtocol?
    private var hideSettingsObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var becomeActiveObserver: NSObjectProtocol?
    private var screenUnlockObserver: NSObjectProtocol?
    private var stopServiceObserver: NSObjectProtocol?
    private var startServiceObserver: NSObjectProtocol?
    private var wakeRewireWorkItem: DispatchWorkItem?

    init(loginLaunch: Bool) {
        self.loginLaunch = loginLaunch
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if BackgroundAgentManager.isOtherInstanceRunning() {
            BackgroundAgentManager.requestShowSettings()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApp.terminate(nil)
            }
            return
        }

        installAppMenu()
        if BackgroundAgentManager.isBackgroundServiceActive() {
            startBackgroundService()
        }
        installHotKeyRefreshObservers()

        showSettingsObserver = DistributedNotificationCenter.default().addObserver(
            forName: BackgroundAgentManager.showSettingsNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.presentSettingsWindow()
        }

        hideSettingsObserver = DistributedNotificationCenter.default().addObserver(
            forName: BackgroundAgentManager.hideSettingsNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.hideSettingsWindow()
        }

        stopServiceObserver = DistributedNotificationCenter.default().addObserver(
            forName: BackgroundAgentManager.stopBackgroundServiceNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.stopBackgroundService()
        }

        startServiceObserver = DistributedNotificationCenter.default().addObserver(
            forName: BackgroundAgentManager.startBackgroundServiceNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.startBackgroundService()
        }

        let store = SettingsStore.shared
        if store.launchAtLogin {
            BackgroundAgentManager.syncLaunchAgent(enabled: true)
        }

        if loginLaunch {
            NSApp.setActivationPolicy(.accessory)
        } else {
            presentSettingsWindow()
        }

        NSLog("Hibernal: started (pid \(ProcessInfo.processInfo.processIdentifier), login=\(loginLaunch))")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if BackgroundAgentManager.consumeTerminationAllowed() {
            return .terminateNow
        }
        if BackgroundAgentManager.isBackgroundServiceActive() {
            hideSettingsWindow()
            return .terminateCancel
        }
        return .terminateNow
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        presentSettingsWindow()
        return true
    }

    private func presentSettingsWindow() {
        if settingsWindow == nil {
            createSettingsWindow()
        }
        guard let window = settingsWindow else { return }

        NSApp.setActivationPolicy(.regular)
        window.deminiaturize(nil)
        window.setIsVisible(true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        hotKeyManager?.reregister()
    }

    private func createSettingsWindow() {
        let hosting = NSHostingController(rootView: SettingsView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "Hibernal"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 480, height: 580))
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.delegate = self
        settingsWindow = window
    }

    private func hideSettingsWindow() {
        settingsWindow?.orderOut(nil)
        if BackgroundAgentManager.isBackgroundServiceActive() {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func resetSettingsWindow() {
        settingsWindow?.orderOut(nil)
        settingsWindow = nil
    }

    private func startBackgroundService() {
        if statusItem == nil {
            installStatusItem()
        } else {
            rewireStatusItemButton()
        }
        registerHotKey()
        ProcessInfo.processInfo.disableAutomaticTermination("Hibernal background service")
        ProcessInfo.processInfo.disableSuddenTermination()
        NSLog("Hibernal: background service started")
    }

    private func stopBackgroundService() {
        hotKeyManager?.apply(binding: HotKeyBinding(keyCode: 0, modifierFlags: 0))
        removeStatusItem()
        ProcessInfo.processInfo.enableAutomaticTermination("Hibernal background service")
        NSLog("Hibernal: background service stopped")
    }

    private func removeStatusItem() {
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
        statusMenu = nil
    }

    private func buildStatusMenu() -> NSMenu {
        let menu = NSMenu()
        addMenuAction(menu, title: NSLocalizedString("Open Settings", comment: ""), action: #selector(openSettings))
        menu.addItem(.separator())
        addMenuAction(menu, title: NSLocalizedString("Hibernate Now", comment: ""), action: #selector(hibernateNow))
        menu.addItem(.separator())
        addMenuAction(menu, title: NSLocalizedString("Quit", comment: ""), action: #selector(quit))
        return menu
    }

    private func installStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.autosaveName = "com.hibernal.statusitem"
        guard statusItem != nil else { return }
        statusMenu = buildStatusMenu()
        rewireStatusItemButton()
    }

    private func rewireStatusItemButton() {
        guard let item = statusItem else { return }
        StatusBarSupport.makeVisible(item)
        guard let button = item.button else { return }
        if statusMenu == nil {
            statusMenu = buildStatusMenu()
        }
        StatusBarSupport.configure(button: button)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.target = self
        button.action = #selector(statusBarButtonClicked(_:))
    }

    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        rewireStatusItemButton()

        if let event = NSApp.currentEvent,
           event.type == .rightMouseUp || event.modifierFlags.contains(.control),
           let menu = statusMenu {
            let location = NSPoint(x: 0, y: sender.bounds.height + 4)
            menu.popUp(positioning: nil, at: location, in: sender)
            return
        }
        presentSettingsWindow()
    }

    private func installAppMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        let settingsItem = appMenu.addItem(
            withTitle: NSLocalizedString("Settings…", comment: ""),
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        appMenu.addItem(.separator())
        let hideItem = appMenu.addItem(
            withTitle: NSLocalizedString("Hide to Menu Bar", comment: ""),
            action: #selector(hideToMenuBar),
            keyEquivalent: "q"
        )
        hideItem.target = self

        NSApp.mainMenu = mainMenu
    }

    private func addMenuAction(
        _ menu: NSMenu,
        title: String,
        action: Selector,
        keyEquivalent: String = ""
    ) {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
    }

    func windowWillClose(_ notification: Notification) {
        hideSettingsWindow()
    }

    @objc private func openSettings() {
        presentSettingsWindow()
    }

    @objc private func hibernateNow() {
        performHibernateIfEnabled()
    }

    @objc private func hideToMenuBar() {
        hideSettingsWindow()
    }

    @objc private func quit() {
        BackgroundAgentManager.markTerminationAllowed()
        NSApp.terminate(nil)
    }

    private func registerHotKey() {
        if hotKeyManager == nil {
            hotKeyManager = HotKeyManager { [weak self] in
                self?.performHibernateIfEnabled()
            }
        }
        let store = SettingsStore.shared
        if store.hibernateEnabled {
            hotKeyManager?.apply(binding: store.hotKey)
        } else {
            hotKeyManager?.apply(binding: HotKeyBinding(keyCode: 0, modifierFlags: 0))
        }

        if settingsObserver == nil {
            settingsObserver = DistributedNotificationCenter.default().addObserver(
                forName: BackgroundAgentManager.settingsChangedNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.registerHotKey()
            }
        }
    }

    private func installHotKeyRefreshObservers() {
        let workspace = NSWorkspace.shared.notificationCenter
        wakeObserver = workspace.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleSystemWake()
        }

        becomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.hotKeyManager?.reregister()
        }

        screenUnlockObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.hotKeyManager?.reregister()
        }
    }

    private func handleSystemWake() {
        NSLog("Hibernal: system wake detected")
        resetSettingsWindow()
        guard BackgroundAgentManager.isBackgroundServiceActive() else { return }

        rewireStatusItemButton()
        hotKeyManager?.reregister()

        wakeRewireWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.rewireStatusItemButton()
            self.hotKeyManager?.reregister()
        }
        wakeRewireWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    private func performHibernateIfEnabled() {
        let store = SettingsStore.shared
        guard store.hibernateEnabled else { return }
        HibernateRunner.trigger(
            restoreAfterWake: store.restoreAfterWake,
            ejectDrives: store.ejectDrivesBeforeHibernate
        )
    }
}