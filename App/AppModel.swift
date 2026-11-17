import AppKit
import Foundation
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published private(set) var presentation: PresentationPreferences
    /// The latest complete reading of the system; nil until the first one arrives.
    @Published var observation: ServiceObservation?
    /// The action in progress. Service actions own the displayed phase until they finish.
    @Published var operation: ServiceOperation?
    /// The last failed service action. Stays visible after its alert, until the next attempt.
    @Published var operationError: String?
    @Published var errorMessage: String?
    @Published var settingsErrorMessage: String?
    @Published var loginStatus = SMAppService.Status.notRegistered
    private(set) var readyToQuit = false

    private let defaults: UserDefaults
    private let observeService: @MainActor () async -> ServiceObservation
    private let stopForQuit: @MainActor () async throws -> Void
    private var polling: Task<Void, Never>?
    /// Incremented by every reading and every action, so an older reading never overwrites newer state.
    private var generation = 0
    private var presented = false

    init(defaults: UserDefaults = .standard,
         observeService: @escaping @MainActor () async -> ServiceObservation = { await ServiceObservation.read() },
         stopForQuit: @escaping @MainActor () async throws -> Void = { try await SystemIntegration.stopForQuit() }) {
        self.defaults = defaults
        self.observeService = observeService
        self.stopForQuit = stopForQuit
        presentation = PresentationPreferences(defaults: defaults)
    }

    var phase: ServicePhase { ServicePhase(operation: operation, observation: observation) }
    var busy: Bool { operation != nil }
    /// launchd has the service loaded, working or not: the primary action is Turn off.
    var serviceOn: Bool { observation?.service.loaded ?? false }
    var hasError: Bool { phase.isError || operationError != nil }

    let mutaVersion: String = {
        guard let url = Bundle.main.url(forResource: "muta", withExtension: "version"),
              let data = try? Data(contentsOf: url),
              let pin = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let tag = pin["tag"] else { return L10n.text("unknown version") }
        return tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    }()

    // MARK: Presentation

    func setMenuBarVisible(_ visible: Bool) {
        presentation.showInMenuBar = visible
        presentation.save(to: defaults)
    }

    func setDockVisible(_ visible: Bool) {
        let policy: NSApplication.ActivationPolicy = visible ? .regular : .accessory
        guard NSApp.activationPolicy() == policy || NSApp.setActivationPolicy(policy) else {
            settingsErrorMessage = L10n.text("The Dock visibility could not be changed. Try again.")
            return
        }
        presentation.showInDock = visible
        presentation.save(to: defaults)
    }

    // MARK: Observation

    static let visibleInterval = Duration.seconds(1)
    static let backgroundInterval = Duration.seconds(5)

    func start() {
        guard polling == nil else { return }
        _ = NSApp.setActivationPolicy(presentation.showInDock ? .regular : .accessory)
        restartPolling()
    }

    /// Reads every second while a Tetherline window or panel is visible, otherwise
    /// every five seconds for the menu bar icon. Becoming visible reads at once.
    func setPresented(_ visible: Bool) {
        guard visible != presented else { return }
        presented = visible
        if polling != nil { restartPolling() }
    }

    private func restartPolling() {
        polling?.cancel()
        polling = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                try? await Task.sleep(for: self.presented ? Self.visibleInterval : Self.backgroundInterval)
            }
        }
    }

    /// Skipped while an action runs: the action publishes its own outcome.
    func refresh() async {
        guard operation == nil else { return }
        await observe()
    }

    private func observe() async {
        generation += 1
        let reading = generation
        let next = await observeService()
        guard reading == generation else { return }
        observation = next
        loginStatus = LoginItem.app.status
    }

    // MARK: Actions

    func enable() {
        perform(.enabling) { try await SystemIntegration.enable() }
    }

    func disable() {
        perform(.disabling) { try await SystemIntegration.disable() }
    }

    func setLogin(_ enabled: Bool) {
        perform(.changingLoginItem) { try await LoginItem.app.setEnabled(enabled) }
    }

    func uninstall() {
        perform(.uninstalling) {
            try await LoginItem.app.setEnabled(false)
            try await SystemIntegration.uninstall()
            try SystemIntegration.removeUserData()
            self.polling?.cancel()
            self.readyToQuit = true // The service is already stopped and removed.
            let alert = NSAlert()
            alert.messageText = L10n.text("Tetherline has been uninstalled")
            alert.informativeText = L10n.text("The log and settings have been removed. Move Tetherline.app from Applications to the Trash.")
            alert.addButton(withTitle: L10n.text("Show in Finder and quit"))
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
            NSApp.terminate(nil)
        }
    }

    /// Runs one action at a time. The final reading is published before the action
    /// ends, so the UI goes straight from the action's phase to the real outcome.
    func perform(_ operation: ServiceOperation, _ body: @escaping @MainActor () async throws -> Void) {
        guard self.operation == nil else { return }
        self.operation = operation
        generation += 1 // A reading already in flight predates the action.
        if operation.affectsService { operationError = nil }
        Task {
            do { try await body() }
            catch { report(error, during: operation) }
            await observe()
            self.operation = nil
        }
    }

    private func report(_ error: Error, during operation: ServiceOperation) {
        let message = error.localizedDescription
        switch operation {
        case .changingLoginItem, .uninstalling: settingsErrorMessage = message
        case .enabling, .disabling, .quitting:
            operationError = message
            errorMessage = message
        }
    }

    func prepareToQuit() async throws {
        guard operation == nil else {
            throw TetherlineError.message(L10n.text("Wait for the current operation to finish, then quit again."))
        }
        operation = .quitting
        generation += 1
        do {
            try await stopForQuit()
            polling?.cancel()
            readyToQuit = true // The app terminates while still showing "Turning off…".
        } catch {
            operationError = error.localizedDescription
            await observe()
            operation = nil
            throw error
        }
    }

    func showLog() {
        guard FileManager.default.fileExists(atPath: SystemIntegration.logURL.path) else {
            errorMessage = L10n.text("The log will appear after you enable tethering for the first time.")
            return
        }
        NSWorkspace.shared.open(SystemIntegration.logURL)
    }
}
