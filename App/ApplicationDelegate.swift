import AppKit
import Combine
import SwiftUI

@MainActor
final class ApplicationDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let model: AppModel
    private(set) var statusItem: NSStatusItem?
    var isMenuBarVisible: Bool { statusItem != nil }
    let popover = NSPopover()
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var subscriptions = Set<AnyCancellable>()
    private var terminationRequested = false

    init(model: AppModel = .shared) {
        self.model = model
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureApplicationMenu()
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        let controller = NSHostingController(rootView: MenuContent(model: model, openSettings: { [weak self] in
            self?.showSettings()
        }))
        // NSPopover must know the real size before it chooses its screen anchor.
        // The hosting controller's initial 320 × 320 frame is only a placeholder.
        controller.view.setFrameSize(controller.view.fittingSize)
        popover.contentViewController = controller
        applyPresentation(model.presentation)
        model.$presentation.removeDuplicates().sink { [weak self] preferences in
            Task { @MainActor [weak self] in self?.applyPresentation(preferences) }
        }.store(in: &subscriptions)
        model.objectWillChange.debounce(for: .milliseconds(50), scheduler: RunLoop.main).sink { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateIcon()
                self?.updatePopoverSize()
            }
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.popover.performClose(nil) }
            }.store(in: &subscriptions)
        ApplicationWindows.shared.onVisibilityChange = { [weak self] in self?.updatePresented() }
        model.start()
        if !model.presentation.showInMenuBar && !CommandLine.arguments.contains("--login-item") { reopen() }
    }

    private func applyPresentation(_ preferences: PresentationPreferences) {
        _ = NSApp.setActivationPolicy(preferences.showInDock ? .regular : .accessory)
        if preferences.showInMenuBar {
            if statusItem == nil {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                item.button?.target = self
                item.button?.action = #selector(togglePopover)
                statusItem = item
            }
            updateIcon()
        } else if let item = statusItem {
            popover.performClose(nil)
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    private func updateIcon() {
        let phase = model.phase
        statusItem?.button?.image = MenuIcon.make(phase: phase, failed: model.operationError != nil && !model.busy)
        statusItem?.button?.toolTip = "Tetherline: \(phase.headline)"
        statusItem?.button?.setAccessibilityLabel("Tetherline: \(phase.headline)")
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else {
            updatePopoverSize()
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func updatePopoverSize() {
        guard let view = popover.contentViewController?.view else { return }
        view.layoutSubtreeIfNeeded()
        let size = view.fittingSize
        guard size.width > 0, size.height > 0, popover.contentSize != size else { return }
        popover.contentSize = size
    }

    /// Polling follows what the user can see: the panel or a Tetherline window.
    private func updatePresented() {
        model.setPresented(popover.isShown || ApplicationWindows.shared.hasVisibleWindow)
    }

    func popoverDidShow(_ notification: Notification) {
        updatePresented()
        // Transient popovers alone do not dismiss when another menu bar item is clicked.
        // Mouse monitoring needs no Accessibility permission; key events stay local.
        removeEventMonitors()
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.popover.performClose(nil) }
        }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                guard let self else { return false }
                if event.type == .keyDown {
                    if event.keyCode == 53, self.popover.contentViewController?.view.window?.attachedSheet == nil {
                        self.popover.performClose(nil)
                        return true
                    }
                } else if event.window !== self.popover.contentViewController?.view.window,
                          event.window !== self.statusItem?.button?.window,
                          event.window?.sheetParent !== self.popover.contentViewController?.view.window {
                    self.popover.performClose(nil)
                }
                return false
            }
            return consumed ? nil : event
        }
    }

    func popoverDidClose(_ notification: Notification) {
        removeEventMonitors()
        updatePresented()
    }

    private func removeEventMonitors() {
        if let localEventMonitor { NSEvent.removeMonitor(localEventMonitor) }
        if let globalEventMonitor { NSEvent.removeMonitor(globalEventMonitor) }
        localEventMonitor = nil
        globalEventMonitor = nil
    }

    private func reopen() {
        if model.presentation.reopenWindowID == "settings" { showSettings() }
        else { ApplicationWindows.shared.showConnection(model: model) }
    }

    @objc private func showSettings() {
        popover.performClose(nil)
        ApplicationWindows.shared.showSettings(model: model)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        reopen()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if model.readyToQuit { return .terminateNow }
        guard !model.busy, !terminationRequested else {
            NSSound.beep()
            return .terminateCancel
        }
        terminationRequested = true
        Task { @MainActor in
            do {
                try await model.prepareToQuit()
                sender.terminate(nil) // readyToQuit permits the second request immediately.
            } catch {
                terminationRequested = false
                // Dock / Cmd-Q can be used with every app window closed.
                let alert = NSAlert()
                alert.messageText = L10n.text("Tetherline could not quit")
                alert.informativeText = L10n.text("The app is still open because tethering could not be stopped.") + "\n\n" + error.localizedDescription
                alert.addButton(withTitle: L10n.text("OK"))
                sender.activate(ignoringOtherApps: true)
                alert.runModal()
            }
        }
        // Return to the event loop while stopping. terminateLater enters a nested
        // loop that can block MainActor tasks when Quit itself came from a task.
        return .terminateCancel
    }

    private func configureApplicationMenu() {
        let menu = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu()
        let settings = NSMenuItem(title: L10n.text("Settings…"), action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        applicationMenu.addItem(settings)
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(withTitle: L10n.text("Quit Tetherline"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        applicationItem.submenu = applicationMenu
        menu.addItem(applicationItem)
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: L10n.text("Edit"))
        editMenu.addItem(withTitle: L10n.text("Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: L10n.text("Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        menu.addItem(editItem)
        NSApp.mainMenu = menu
    }
}

@MainActor
final class ApplicationWindows: NSObject, NSWindowDelegate {
    static let shared = ApplicationWindows()
    private var settingsWindow: NSWindow?
    private var connectionWindow: NSWindow?
    var onVisibilityChange: (() -> Void)?

    var hasVisibleWindow: Bool {
        [settingsWindow, connectionWindow].contains { $0?.isVisible == true && $0?.isMiniaturized == false }
    }

    func showSettings(model: AppModel) {
        if settingsWindow == nil {
            settingsWindow = makeWindow(title: L10n.text("Settings"), view: SettingsView(model: model))
        }
        present(settingsWindow!)
    }

    func showConnection(model: AppModel) {
        if connectionWindow == nil {
            connectionWindow = makeWindow(title: "Tetherline", view: MenuContent(model: model))
        }
        present(connectionWindow!)
    }

    private func makeWindow<Content: View>(title: String, view: Content) -> NSWindow {
        let controller = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: controller)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(controller.view.fittingSize)
        window.center()
        return window
    }

    private func present(_ window: NSWindow) {
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onVisibilityChange?()
    }

    func windowWillClose(_ notification: Notification) {
        // The window is still visible during this callback.
        Task { @MainActor in self.onVisibilityChange?() }
    }

    func windowDidMiniaturize(_ notification: Notification) { onVisibilityChange?() }
    func windowDidDeminiaturize(_ notification: Notification) { onVisibilityChange?() }
}
