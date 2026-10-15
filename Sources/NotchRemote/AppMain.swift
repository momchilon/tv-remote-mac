import AppKit
import Combine
import NotchUI
import RemoteKit

@MainActor
@main
struct NotchRemoteApp {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = PanelModel()
    private let remote = SamsungRemote()
    private var controller: MenuBarController!
    private var subscriptions = Set<AnyCancellable>()
    private var observers: [NSObjectProtocol] = []
    private var activeHost = ""
    private var wakeTask: Task<Void, Never>?
    private var profiles: SavedRemotesStore!
    private var discoveredDevices: [String: DiscoveredTV] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--setup-host"), arguments.indices.contains(index + 1) {
            UserDefaults.standard.set(arguments[index + 1], forKey: "tvHost")
        }
        profiles = SavedRemotesStore()
        model.savedRemotes = profiles.remotes
        model.host = profiles.selectedHost
        model.selectedRemoteHost = profiles.selectedHost
        model.remoteName = profiles.remotes.first { $0.host == profiles.selectedHost }?.name ?? ""
        activeHost = model.host
        if let index = arguments.firstIndex(of: "--setup-mac"), arguments.indices.contains(index + 1), !activeHost.isEmpty {
            UserDefaults.standard.set(arguments[index + 1], forKey: "mac-" + activeHost)
        }
        updateWakeAvailability()
        controller = MenuBarController(model: model)
        wireActions()
        remote.$status.sink { [weak self] status in
            guard let self else { return }
            switch status {
            case .disconnected: self.model.connection = .disconnected
            case .connecting: self.model.connection = .connecting
            case .awaitingApproval: self.model.connection = .approval
            case .connected:
                self.model.connection = .ready
                self.model.notice = ""
                if let mac = self.discoveredDevices[self.activeHost]?.macAddress {
                    UserDefaults.standard.set(mac, forKey: "mac-" + self.activeHost)
                    self.updateWakeAvailability()
                }
            case .failed(let message): self.model.connection = .failed(message)
            }
        }.store(in: &subscriptions)
        remote.onDeviceInfo = { [weak self] _, mac in
            guard let self, let mac else { return }
            UserDefaults.standard.set(mac, forKey: "mac-" + self.activeHost)
            self.updateWakeAvailability()
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.model.cancelDiscovery()
                self?.wakeTask?.cancel()
                self?.remote.disconnect()
            }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.connectAfterDelay() }
        })
        // Connect silently. Only a click on the remote icon opens the popover.
        if !model.host.isEmpty { model.connect() }
    }

    private func wireActions() {
        model.onDiscover = { [weak self] in
            let devices = try await TVDiscovery().discover()
            try Task.checkCancellation()
            self?.discoveredDevices = Dictionary(uniqueKeysWithValues: devices.map { ($0.host, $0) })
            return devices.map { PanelTV(host: $0.host, name: $0.name, model: $0.model) }
        }
        model.onCommand = { [weak self] command in
            self?.remote.send(command)
        }
        model.onConnect = { [weak self] host in
            guard let self else { return }
            guard let saved = self.profiles.save(host: host, name: self.model.remoteName) else { return }
            self.wakeTask?.cancel()
            self.activeHost = host
            self.model.savedRemotes = self.profiles.remotes
            self.model.selectedRemoteHost = host
            self.model.remoteName = saved.name
            self.updateWakeAvailability()
            self.remote.connect(host: host)
        }
        model.onRemoveRemote = { [weak self] host in
            guard let self else { return }
            self.profiles.remove(host: host)
            self.model.savedRemotes = self.profiles.remotes
            if host == self.activeHost {
                self.wakeTask?.cancel()
                self.remote.disconnect()
                self.activeHost = self.profiles.selectedHost
                self.model.selectedRemoteHost = self.activeHost
                self.updateWakeAvailability()
            }
            if self.model.host == host {
                self.model.host = self.profiles.selectedHost
                self.model.remoteName = self.profiles.remotes.first { $0.host == self.model.host }?.name ?? ""
            }
        }
        model.onForget = { [weak self] in
            guard let self else { return }
            self.remote.forget(host: self.model.host.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        model.onWake = { [weak self] in
            guard let self, let mac = UserDefaults.standard.string(forKey: "mac-" + self.activeHost) else { return }
            self.remote.wake(macAddress: mac, host: self.activeHost)
            self.model.notice = "Wake request sent. Waiting for TV…"
            self.connectAfterDelay()
        }
        model.onQuit = { NSApplication.shared.terminate(nil) }
    }

    private func updateWakeAvailability() {
        model.canWake = !(UserDefaults.standard.string(forKey: "mac-" + activeHost) ?? "").isEmpty
    }

    private func connectAfterDelay() {
        wakeTask?.cancel()
        let host = activeHost
        guard !host.isEmpty else { return }
        wakeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled, let self, self.activeHost == host else { return }
            self.remote.connect(host: host)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        return false
    }
    func applicationWillTerminate(_ notification: Notification) {
        model.cancelDiscovery()
        wakeTask?.cancel()
        remote.disconnect()
        controller?.stop()
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
}
