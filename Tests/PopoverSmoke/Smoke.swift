import AppKit
import SwiftUI

@main enum PopoverSmoke {
    @MainActor static func main() {
        let application = NSApplication.shared
        let domain = "pl.tetherline.popover-smoke"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        let model = AppModel(defaults: defaults, stopForQuit: {})
        let delegate = ApplicationDelegate(model: model)
        application.delegate = delegate
        Task { @MainActor in
            await settle()
            for dock in [false, true] {
                model.setDockVisible(dock)
                await settle()
                let button = delegate.statusItem!.button!
                button.performClick(nil)
                await settle()
                checkGeometry(delegate)
                precondition(delegate.popover.contentViewController!.view.window!.isKeyWindow, "Popover keyboard focus")
                print("PASS anchored panel and keyboard focus, Dock=\(dock)")

                // Changing status while open must resize downwards, below the menu bar.
                model.operationError = "Connection status changed. This message increases the panel height."
                await settle()
                checkGeometry(delegate)
                print("PASS panel remains anchored after content growth")
                model.operationError = nil

                button.performClick(nil)
                await settle()
                precondition(!delegate.popover.isShown, "Second icon click closes panel")
                button.performClick(nil)
                await settle()
                let panel = delegate.popover.contentViewController!.view.window!
                let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
                    context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
                    isARepeat: false, keyCode: 53)!
                application.postEvent(escape, atStart: false)
                await settle()
                precondition(!delegate.popover.isShown, "Escape closes panel")
                print("PASS second click and Escape dismiss panel")

                button.performClick(nil)
                await settle()
                let other = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 200, height: 100),
                                     styleMask: [.titled], backing: .buffered, defer: false)
                other.isReleasedWhenClosed = false
                other.orderFront(nil)
                let click = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 50, y: 50),
                    modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: other.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
                application.postEvent(click, atStart: false)
                await settle()
                precondition(!delegate.popover.isShown, "Outside click closes panel")
                other.close()
                print("PASS outside click dismisses panel")

                button.performClick(nil)
                await settle()
                let controller = delegate.popover.contentViewController as! NSHostingController<MenuContent>
                controller.rootView.openSettings!()
                await settle()
                precondition(!delegate.popover.isShown, "Settings closes panel")
                precondition(application.windows.contains { $0.isVisible && $0.title == L10n.text("Settings") })
                for window in application.windows where window.title == L10n.text("Settings") { window.close() }
                print("PASS Settings dismisses panel and opens settings window")
            }
            defaults.removePersistentDomain(forName: domain)
            application.terminate(nil)
        }
        withExtendedLifetime(delegate) { application.run() }
    }

    @MainActor private static func settle() async {
        try? await Task.sleep(for: .milliseconds(500))
    }

    @MainActor private static func checkGeometry(_ delegate: ApplicationDelegate) {
        precondition(delegate.popover.isShown, "Panel opens")
        let view = delegate.popover.contentViewController!.view
        let window = view.window!
        let content = window.convertToScreen(view.convert(view.bounds, to: nil))
        let screen = delegate.statusItem!.button!.window!.screen!
        precondition(abs(delegate.popover.contentSize.width - view.frame.width) < 1, "Measured width")
        precondition(abs(delegate.popover.contentSize.height - view.frame.height) < 1, "Measured height")
        precondition(content.maxY <= screen.visibleFrame.maxY, "Panel content must not cover menu bar: \(content)")
        precondition(content.minY >= screen.visibleFrame.minY, "Panel fits vertically")
        precondition(content.minX >= screen.visibleFrame.minX && content.maxX <= screen.visibleFrame.maxX, "Panel fits horizontally")
    }
}
