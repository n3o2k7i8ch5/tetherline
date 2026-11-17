import AppKit

/// Stands in for the system: returns a chosen reading, optionally holding one back.
@MainActor private final class Probe {
    var value = ServiceObservation()
    var readings = 0
    var held: CheckedContinuation<ServiceObservation, Never>?
    var holdNext = false

    func read() async -> ServiceObservation {
        readings += 1
        if holdNext {
            holdNext = false
            return await withCheckedContinuation { held = $0 }
        }
        return value
    }
}

@main enum ServiceStateSmoke {
    static let connectedStatus = try! MutaStatus(output: "state connected\ninterface utun5\naddress 10.0.0.2\nin 7\nout 8")
    static let connected = ServiceObservation(installation: .current, service: ServiceState(loaded: true, pid: 42), status: connectedStatus)
    static let off = ServiceObservation(installation: .current)
    /// What launchd shows while a job unloads: loaded, engine gone. Looks exactly like a crash.
    static let unloading = ServiceObservation(installation: .current, service: ServiceState(loaded: true))

    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let domain = "pl.tetherline.service-state-test"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }

        try await readingsArePublishedWholeAndInOrder(defaults)
        try await turningOffNeverFlashesAnError(defaults)
        try await failedActionStaysVisibleUntilNextAttempt(defaults)
        try await pollingFollowsVisibility(defaults)
        try await quitWaitsForStop(defaults)
    }

    @MainActor static func readingsArePublishedWholeAndInOrder(_ defaults: UserDefaults) async throws {
        let probe = Probe()
        let model = AppModel(defaults: defaults, observeService: { await probe.read() })
        precondition(model.phase == .checking && model.observation == nil)
        probe.value = connected
        await model.refresh()
        precondition(model.phase == .connected(connectedStatus) && model.serviceOn)

        probe.value = unloading
        await model.refresh()
        guard case .failed = model.phase else { preconditionFailure("A crashed engine must be reported") }
        precondition(model.serviceOn && model.hasError && !model.phase.isConnected)
        print("PASS a crash replaces connection details with a failure; Turn off stays available")

        probe.holdNext = true
        let older = Task { await model.refresh() }
        await wait { probe.held != nil }
        probe.value = off
        await model.refresh()
        probe.held!.resume(returning: connected)
        probe.held = nil
        await older.value
        precondition(model.phase == .off(needsAdministrator: false) && !model.serviceOn)
        print("PASS a late connected reading cannot overwrite a newer off state")
    }

    /// The reported bug: a poll during Turn off saw the unloading job and flashed an error.
    @MainActor static func turningOffNeverFlashesAnError(_ defaults: UserDefaults) async throws {
        let probe = Probe()
        probe.value = connected
        let model = AppModel(defaults: defaults, observeService: { await probe.read() })
        model.setPresented(true)
        model.start()
        await wait { model.phase.isConnected }

        var finishStop: CheckedContinuation<Void, Never>?
        model.perform(.disabling) {
            probe.value = unloading
            await withCheckedContinuation { finishStop = $0 }
            probe.value = off
        }
        precondition(model.phase == .stopping && model.busy)
        await wait { finishStop != nil }
        let readingsBefore = probe.readings
        var phases: [ServicePhase] = []
        await model.refresh() // The panel opening mid-operation must not read either.
        for _ in 0..<150 { // 1.5 s: longer than the one-second polling interval.
            phases.append(model.phase)
            try? await Task.sleep(for: .milliseconds(10))
        }
        precondition(probe.readings == readingsBefore, "No reading may be published during the operation")
        finishStop!.resume()
        while model.busy {
            phases.append(model.phase)
            try? await Task.sleep(for: .milliseconds(1))
        }
        phases.append(model.phase)
        precondition(!phases.contains { $0.isError }, "Error shown while turning off: \(phases)")
        precondition(phases.drop { $0 == .stopping } == [.off(needsAdministrator: false)], "Unexpected phases: \(Set(phases.map(\.headline)))")
        precondition(model.operationError == nil && !model.serviceOn)
        model.setPresented(false)
        print("PASS turning off goes from Turning off… straight to off, without a transient error")

        probe.value = off
        var finishStart: CheckedContinuation<Void, Never>?
        model.perform(.enabling) {
            probe.value = ServiceObservation(installation: .current, service: ServiceState(loaded: true, pid: 42), error: "Socket not ready")
            await withCheckedContinuation { finishStart = $0 }
            probe.value = connected
        }
        await wait { finishStart != nil }
        precondition(model.phase == .starting && !model.hasError)
        finishStart!.resume()
        await wait { !model.busy }
        precondition(model.phase.isConnected)
        print("PASS turning on shows Turning on… until the engine answers")
    }

    @MainActor static func failedActionStaysVisibleUntilNextAttempt(_ defaults: UserDefaults) async throws {
        let probe = Probe()
        probe.value = off
        let model = AppModel(defaults: defaults, observeService: { await probe.read() })
        model.perform(.enabling) { throw TetherlineError.message("Simulated failure") }
        await wait { !model.busy }
        precondition(model.errorMessage == "Simulated failure" && model.operationError == "Simulated failure")
        model.errorMessage = nil // Dismiss the alert as the user would.
        await model.refresh()
        precondition(model.operationError == "Simulated failure" && model.hasError)
        model.perform(.enabling) {}
        precondition(model.operationError == nil, "A new attempt clears the previous failure")
        await wait { !model.busy }
        precondition(!model.hasError)

        model.perform(.changingLoginItem) { throw TetherlineError.message("Login item failed") }
        await wait { !model.busy }
        precondition(model.settingsErrorMessage == "Login item failed" && model.operationError == nil)
        print("PASS a failed action survives alert dismissal; settings failures stay in Settings")
    }

    @MainActor static func pollingFollowsVisibility(_ defaults: UserDefaults) async throws {
        let probe = Probe()
        probe.value = off
        let model = AppModel(defaults: defaults, observeService: { await probe.read() })
        model.start()
        try? await Task.sleep(for: .milliseconds(2300))
        precondition(probe.readings == 1, "Hidden: one reading, then every five seconds (got \(probe.readings))")
        model.setPresented(true)
        try? await Task.sleep(for: .milliseconds(2300))
        precondition((3...4).contains(probe.readings), "Visible: at once, then every second (got \(probe.readings))")
        model.setPresented(false)
        let afterHiding = probe.readings
        try? await Task.sleep(for: .milliseconds(2300))
        precondition(probe.readings == afterHiding + 1)
        print("PASS polling reads every second while visible and every five seconds in the background")
    }

    @MainActor static func quitWaitsForStop(_ defaults: UserDefaults) async throws {
        var stopCalls = 0
        var finishStop: CheckedContinuation<Void, any Error>?
        let model = AppModel(defaults: defaults, observeService: { connected }, stopForQuit: {
            stopCalls += 1
            try await withCheckedThrowingContinuation { finishStop = $0 }
        })
        await model.refresh()
        let cancelledQuit = Task { try await model.prepareToQuit() }
        await wait { finishStop != nil }
        precondition(model.busy && model.phase == .stopping && !model.readyToQuit)
        do {
            try await model.prepareToQuit()
            preconditionFailure("A second quit must not start another stop")
        } catch { precondition(stopCalls == 1) }
        finishStop!.resume(throwing: TetherlineError.message("Could not stop"))
        finishStop = nil
        do {
            try await cancelledQuit.value
            preconditionFailure("A failed stop must keep the app open")
        } catch {}
        precondition(!model.readyToQuit && !model.busy && model.phase.isConnected && model.operationError == "Could not stop")
        print("PASS quit waits for stop; a second quit is rejected; failure keeps the app open")

        let successfulQuit = Task { try await model.prepareToQuit() }
        await wait { finishStop != nil }
        finishStop!.resume()
        try await successfulQuit.value
        precondition(model.readyToQuit && model.phase == .stopping)
        print("PASS quit is allowed only after stop succeeds")
    }

    @MainActor static func wait(_ predicate: () -> Bool) async {
        for _ in 0..<250 {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
        preconditionFailure("Timed out waiting for condition")
    }
}
