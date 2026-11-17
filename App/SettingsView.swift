import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var showUninstall = false

    private var license: String {
        guard let url = Bundle.main.url(forResource: "muta-LICENSE", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return L10n.text("The muta license could not be found.")
        }
        return text
    }

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 12) {
                Image(systemName: "gearshape")
                    .font(.system(size: 24, weight: .medium))
                    .frame(width: 46, height: 46)
                    .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Settings").font(.system(size: 22, weight: .semibold))
                    Text("Tetherline").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if model.busy { ProgressView().controlSize(.small).accessibilityLabel("Working") }
            }

            VStack(alignment: .leading, spacing: 14) {
                Text("App visibility").font(.system(size: 13, weight: .semibold))
                Toggle(isOn: Binding(
                    get: { model.presentation.showInMenuBar }, set: model.setMenuBarVisible
                )) {
                    Text("Show in menu bar").font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .toggleStyle(.switch)
                Divider()
                Toggle(isOn: Binding(
                    get: { model.presentation.showInDock }, set: model.setDockVisible
                )) {
                    Text("Show in Dock").font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .toggleStyle(.switch)
                if !model.presentation.showInMenuBar && !model.presentation.showInDock {
                    Text("Both icons are hidden. Reopen Tetherline from Applications to access Settings.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16).settingsCard()

            VStack(alignment: .leading, spacing: 12) {
                Text("Startup").font(.system(size: 13, weight: .semibold))
                Toggle(isOn: Binding(
                    get: { model.loginStatus == .enabled || model.loginStatus == .requiresApproval },
                    set: { model.setLogin($0) }
                )) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Launch at login").font(.system(size: 13, weight: .medium))
                        Text("Open Tetherline automatically when you sign in.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .toggleStyle(.switch).disabled(model.busy)
                if model.loginStatus == .requiresApproval {
                    Text("Allow Tetherline to run in the background.")
                        .font(.caption).foregroundStyle(.secondary)
                    ActionButton(title: L10n.text("Open System Settings"), systemImage: "gearshape") {
                        SMAppService.openSystemSettingsLoginItems()
                    }
                }
            }
            .padding(16).settingsCard()

            VStack(alignment: .leading, spacing: 14) {
                Text("About").font(.system(size: 13, weight: .semibold))
                HStack(spacing: 12) {
                    Image(systemName: "personalhotspot").font(.system(size: 26)).frame(width: 34)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(verbatim: "Tetherline 0.1.0").font(.system(size: 15, weight: .semibold))
                        Text("Android internet, over USB.").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(verbatim: "muta \(model.mutaVersion)").font(.caption).foregroundStyle(.secondary)
                }
                Link(destination: URL(string: "https://github.com/jost-s/macos-usb-tether-android")!) {
                    Label("muta — source code and releases", systemImage: "arrow.up.right")
                }
                .buttonStyle(ActionButtonStyle(tone: .secondary))
                Divider()
                DisclosureGroup("Open-source license") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("The muta engine is included without source modifications.")
                            .font(.caption).foregroundStyle(.secondary)
                        ScrollView {
                            Text(license).font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }.frame(height: 150)
                    }.padding(.top, 10)
                }.font(.system(size: 12))
            }
            .padding(16).settingsCard()

            HStack(spacing: 20) {
                Text("Stops tethering and closes the app.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                ActionButton(title: L10n.text("Quit Tetherline"), tone: .secondary) {
                    NSApp.terminate(nil)
                }.disabled(model.busy)
            }

            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Uninstall Tetherline").font(.system(size: 13, weight: .medium))
                    Text("Remove the background service and app data.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                ActionButton(title: L10n.text("Uninstall…"), tone: .attention, role: .destructive) { showUninstall = true }
                    .disabled(model.busy)
            }
        }
        .padding(24).frame(width: 520)
        }
        .frame(width: 520, height: 640)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showUninstall) { uninstallConfirmation }
        .alert("Tetherline", isPresented: Binding(
            get: { model.settingsErrorMessage != nil },
            set: { if !$0 { model.settingsErrorMessage = nil } }
        )) {
            Button("OK") { model.settingsErrorMessage = nil }
        } message: { Text(model.settingsErrorMessage ?? "") }
    }

    var uninstallConfirmation: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Uninstall Tetherline?").font(.title2.bold())
            Text("This will disconnect USB tethering, remove the background service and login item, and delete the log and settings. You can then move the app to the Trash.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                ActionButton(title: L10n.text("Cancel"), tone: .secondary, role: .cancel) {
                    showUninstall = false
                }.keyboardShortcut(.cancelAction)
                Spacer()
                ActionButton(title: L10n.text("Uninstall"), systemImage: "trash", tone: .attention, role: .destructive) {
                    showUninstall = false
                    model.uninstall()
                }
            }
        }.padding(28).frame(width: 440)
            .background(Color(nsColor: .windowBackgroundColor))
    }
}

private extension View {
    func settingsCard() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.primary.opacity(0.06)))
    }
}
