import AppKit
import Combine
import SwiftUI

final class SettingsModel: ObservableObject {
    static let shared = SettingsModel()

    private let store = SettingsStore.shared

    @Published var hibernateEnabled: Bool
    @Published var restoreAfterWake: Bool
    @Published var launchAtLogin: Bool
    @Published var keepAwakeOnPowerAdapter: Bool
    @Published var ejectDrivesBeforeHibernate: Bool
    @Published var hotKeyDisplayString: String
    @Published var backgroundAgentRunning: Bool = false
    @Published var privilegedHelperReady: Bool = false

    private var captureMonitor: Any?
    private var capturePanel: NSPanel?

    private init() {
        hibernateEnabled = store.hibernateEnabled
        restoreAfterWake = store.restoreAfterWake
        launchAtLogin = store.launchAtLogin
        keepAwakeOnPowerAdapter = store.keepAwakeOnPowerAdapter
        ejectDrivesBeforeHibernate = store.ejectDrivesBeforeHibernate
        hotKeyDisplayString = store.hotKeyDisplayString()
    }

    func persist() {
        store.hibernateEnabled = hibernateEnabled
        store.restoreAfterWake = restoreAfterWake
        store.launchAtLogin = launchAtLogin
        store.keepAwakeOnPowerAdapter = keepAwakeOnPowerAdapter
        store.ejectDrivesBeforeHibernate = ejectDrivesBeforeHibernate
        BackgroundAgentManager.ensureRunning()
        BackgroundAgentManager.notifySettingsChanged()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLogin = enabled
        store.launchAtLogin = enabled
        BackgroundAgentManager.syncLaunchAgent(enabled: enabled)
        if enabled {
            BackgroundAgentManager.ensureRunning()
        }
        BackgroundAgentManager.notifySettingsChanged()
    }

    func hibernateNow() {
        guard hibernateEnabled else { return }
        BackgroundAgentManager.ensureRunning()
        HibernateRunner.trigger(
            restoreAfterWake: restoreAfterWake,
            ejectDrives: ejectDrivesBeforeHibernate
        )
    }

    func hideToMenuBar() {
        BackgroundAgentManager.requestHideSettings()
        refreshBackgroundStatus()
    }

    func quitApp() {
        BackgroundAgentManager.stopApp()
    }

    func stopBackgroundService() {
        BackgroundAgentManager.requestStopBackgroundService()
        refreshBackgroundStatus()
    }

    func restartBackgroundAgent() {
        BackgroundAgentManager.requestStartBackgroundService()
        refreshBackgroundStatus()
    }

    func refreshBackgroundStatus() {
        backgroundAgentRunning = BackgroundAgentManager.isBackgroundServiceActive()
        privilegedHelperReady = PrivilegedHelperManager.isReady
    }

    func setKeepAwakeOnPowerAdapter(_ enabled: Bool) {
        keepAwakeOnPowerAdapter = enabled
        store.keepAwakeOnPowerAdapter = enabled
        PowerSettingsRunner.setKeepAwakeOnPowerAdapter(enabled)
        persist()
    }

    func showPowerSettingsInTerminal() {
        PowerSettingsRunner.openTerminalWithPmsetStatus()
    }

    func beginHotKeyCapture() {
        endHotKeyCapture()

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 120),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = NSLocalizedString("New Shortcut", comment: "")
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.center()

        let label = NSTextField(
            labelWithString: NSLocalizedString("Press the new key combination.\nEscape to cancel.", comment: "")
        )
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView?.addSubview(label)
        if let contentView = panel.contentView {
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
                label.widthAnchor.constraint(equalTo: contentView.widthAnchor, constant: -24),
            ])
        }

        capturePanel = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        captureMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 {
                self.endHotKeyCapture()
                return nil
            }
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard !flags.isEmpty else { return nil }

            self.store.hotKey = HotKeyBinding(
                keyCode: event.keyCode,
                modifierFlags: HotKeyFormatter.normalizedModifiers(from: flags.rawValue).rawValue
            )
            self.hotKeyDisplayString = self.store.hotKeyDisplayString()
            self.persist()
            self.endHotKeyCapture()
            return nil
        }
    }

    private func endHotKeyCapture() {
        if let captureMonitor {
            NSEvent.removeMonitor(captureMonitor)
            self.captureMonitor = nil
        }
        capturePanel?.close()
        capturePanel = nil
    }
}