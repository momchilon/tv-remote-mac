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

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--setup-host"), arguments.indices.contains(index + 1) {
            UserDefaults.standard.set(arguments[index + 1], forKey: "tvHost")
        }
        model.host = UserDefaults.standard.string(forKey: "tvHost") ?? ""
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
            case .connected: self.model.connection = .ready; self.model.notice = ""
            case .failed(let message): self.model.connection = .failed(message)
            }
        }.store(in: &subscriptions)
        remote.onDeviceInfo = { [weak self] _, mac in
            guard let self, let mac else { return }
            UserDefaults.standard.set(mac, forKey: "mac-" + self.activeHost)
            self.updateWakeAvailability()
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.wakeTask?.cancel(); self?.remote.disconnect() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.connectAfterDelay() }
        })
        // Connect silently. Only a click on the remote icon opens the popover.
        if !model.host.isEmpty { model.connect() }
    }

    private func wireActions() {
        model.onCommand = { [weak self] command in
            guard let key = RemoteKey(rawValue: command.rawValue) else { return }
            self?.remote.send(key)
        }
        model.onConnect = { [weak self] host in
            guard let self else { return }
            self.wakeTask?.cancel()
            self.activeHost = host
            UserDefaults.standard.set(host, forKey: "tvHost")
            self.updateWakeAvailability()
            self.remote.connect(host: host)
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
        wakeTask?.cancel()
        remote.disconnect()
        controller?.stop()
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
}
