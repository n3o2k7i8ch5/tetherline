import AppKit

@main enum QuitSmoke {
    @MainActor static func main() {
        let app = NSApplication.shared
        let domain = "pl.tetherline.quit-smoke"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        var stopped = false
        var finishStop: CheckedContinuation<Void, Never>?
        let model = AppModel(defaults: defaults, observeService: { ServiceObservation() }, stopForQuit: {
            await withCheckedContinuation { finishStop = $0 }
            stopped = true
        })
        let delegate = ApplicationDelegate(model: model)
        app.delegate = delegate
        let observer = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                                              object: app, queue: .main) { _ in
            MainActor.assumeIsolated {
                precondition(stopped && model.readyToQuit)
                UserDefaults(suiteName: domain)!.removePersistentDomain(forName: domain)
                print("PASS AppKit termination waits for service stop before exiting")
            }
        }
        Task { @MainActor in
            for _ in 0..<100 {
                if finishStop != nil { break }
                try? await Task.sleep(for: .milliseconds(20))
            }
            precondition(finishStop != nil && model.busy && !model.readyToQuit && !stopped)
            print("PASS app remains alive while service shutdown is pending")
            finishStop!.resume()
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            // Exercise the same termination request as the UI, including a Task caller.
            app.terminate(nil)
        }
        withExtendedLifetime((delegate, observer)) { app.run() }
    }
}
