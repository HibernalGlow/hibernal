import SwiftUI

struct SettingsView: View {
    @ObservedObject private var store = SettingsModel.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Configure hibernate here, then close this window. The app stays in the menu bar and keeps your shortcut active.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Circle()
                    .fill(store.backgroundAgentRunning ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(store.backgroundAgentRunning
                     ? "Background service is running (menu bar + shortcut)"
                     : "Background service is stopped")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Restart App") {
                    store.restartBackgroundAgent()
                }
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(store.privilegedHelperReady ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(store.privilegedHelperReady
                     ? "Privileged helper installed — hibernate won't ask for your password"
                     : "First hibernate will ask for your password once to install the helper")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Look for a small moon icon at the top-right of your screen. On MacBooks with a notch, it may be inside the menu bar \"•••\" overflow section — click the arrow at the far right of the menu bar to find it.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("Enable hibernate", isOn: $store.hibernateEnabled)
                .onChange(of: store.hibernateEnabled) { _ in store.persist() }

            Toggle("Restore normal sleep (hibernatemode 3) after wake", isOn: $store.restoreAfterWake)
                .onChange(of: store.restoreAfterWake) { _ in store.persist() }

            Toggle("Eject external drives before hibernate", isOn: $store.ejectDrivesBeforeHibernate)
                .onChange(of: store.ejectDrivesBeforeHibernate) { _ in store.persist() }

            Text("Safely ejects USB, Thunderbolt, and SD card volumes before sleeping. Network drives are not affected.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("Keep awake on power adapter", isOn: $store.keepAwakeOnPowerAdapter)
                .onChange(of: store.keepAwakeOnPowerAdapter) { value in
                    store.setKeepAwakeOnPowerAdapter(value)
                }

            Text("Prevents idle sleep while plugged in (pmset -c sleep 0). Turning off restores a 10-minute AC sleep timer.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("Start on login", isOn: $store.launchAtLogin)
                .onChange(of: store.launchAtLogin) { value in
                    store.setLaunchAtLogin(value)
                }

            VStack(alignment: .leading, spacing: 8) {
                Text("Keyboard shortcut")
                    .font(.headline)

                Text(store.hotKeyDisplayString)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 6)
                    .background(Color(nsColor: .quaternaryLabelColor).opacity(0.25))
                    .cornerRadius(6)

                Button("Change Shortcut…") {
                    store.beginHotKeyCapture()
                }
            }

            HStack {
                Button("View pmset in Terminal") {
                    store.showPowerSettingsInTerminal()
                }
                Spacer()
                Button("Stop Background Service") {
                    store.stopBackgroundService()
                }
                Button("Quit App") {
                    store.quitApp()
                }
            }

            HStack {
                Spacer()
                Button("Hibernate Now") {
                    store.hibernateNow()
                }
                .disabled(!store.hibernateEnabled)
            }

            Text("Quit the app before moving it to Applications.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(width: 480, height: 580)
        .onAppear {
            store.refreshBackgroundStatus()
        }
    }
}