import Foundation
import Combine
import RemoteKit

// A single allowlist from the UI through to the wire; no silently dropped mappings.
public typealias PanelCommand = RemoteKey

public enum PanelConnection: Equatable {
    case disconnected, connecting, approval, ready, failed(String)
}

public struct PanelTV: Equatable, Identifiable, Sendable {
    public let host: String
    public let name: String
    public let model: String
    public var id: String { host }
    public init(host: String, name: String, model: String) {
        self.host = host; self.name = name; self.model = model
    }
}

@MainActor
public final class PanelModel: ObservableObject {
    @Published public var expanded = false
    @Published public var fullRemote = false
    @Published public var showingMoreControls = false
    @Published public var controlQuery = ""
    @Published public var settings = false
    @Published public var confirmingPower = false
    @Published public var host = ""
    @Published public var remoteName = ""
    @Published public var savedRemotes: [SavedRemote] = []
    @Published public var selectedRemoteHost = ""
    public var activeRemoteName: String {
        savedRemotes.first { $0.host == selectedRemoteHost }?.name ?? "Samsung"
    }
    public var onRemoveRemote: ((String) -> Void)?
    @Published public var canWake = false
    @Published public var notice = ""
    @Published public var connection: PanelConnection = .disconnected {
        didSet { if connection != .ready { confirmingPower = false } }
    }
    @Published public private(set) var discovering = false
    @Published public private(set) var discoveredTVs: [PanelTV] = []
    @Published public private(set) var discoveryNotice = "Find Samsung TVs on your local network."
    public var onDiscover: (() async throws -> [PanelTV])?
    private var discoveryTask: Task<Void, Never>?
    public var onCommand: ((PanelCommand) -> Void)?
    public var onConnect: ((String) -> Void)?
    public var onWake: (() -> Void)?
    public var onForget: (() -> Void)?
    public var onQuit: (() -> Void)?

    public init() {}
    public static func height(settings: Bool, fullRemote: Bool = false) -> Double { settings ? 480 : (fullRemote ? 640 : 250) }
    public static func width(settings: Bool, fullRemote: Bool = false) -> Double { !settings && fullRemote ? 520 : 300 }
    public var panelWidth: Double { Self.width(settings: settings, fullRemote: fullRemote) }
    public var panelHeight: Double { Self.height(settings: settings, fullRemote: fullRemote) }
    public func toggleFullRemote() { controlQuery = ""; showingMoreControls = false; fullRemote.toggle() }
    public var ready: Bool { connection == .ready }
    public var busy: Bool { connection == .connecting || connection == .approval }
    public var keepsOpen: Bool { settings || confirmingPower || busy }
    public var statusDetail: String {
        if case .failed(let message) = connection { return message }
        if !notice.isEmpty { return notice }
        switch connection {
        case .approval: return "Choose Allow on the TV’s connection prompt."
        case .connecting: return "Connecting over your local network."
        default: return "Turn on your TV, then reconnect."
        }
    }

    public func send(_ command: PanelCommand) {
        guard ready, command != .power else { return }
        onCommand?(command)
    }

    public func requestPower() {
        if ready { confirmingPower = true }
        else if canWake { onWake?() }
        else { notice = "Turn on your TV with its remote, then reconnect." }
    }

    public func confirmPowerOff() {
        guard confirmingPower, ready else { confirmingPower = false; return }
        confirmingPower = false
        onCommand?(.power)
    }

    public func connect() {
        guard validateHost() else { return }
        let clean = host
        cancelDiscovery()
        notice = ""
        connection = .connecting
        settings = false
        onConnect?(clean)
    }

    public func findTVs() {
        guard !discovering, let scan = onDiscover else { return }
        discovering = true
        discoveredTVs = []
        discoveryNotice = "Searching your local network…"
        discoveryTask = Task { [weak self] in
            do {
                let results = try await scan()
                guard !Task.isCancelled, let self else { return }
                self.discoveredTVs = results
                self.discovering = false
                self.discoveryNotice = results.isEmpty
                    ? "No TVs found. Turn the TV on, check local-network permission, or enter its IP."
                    : "Choose a TV, then Connect."
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.discovering = false
                self.discoveryNotice = "Search failed. Check local-network access or enter the TV’s IP."
            }
        }
    }

    public func selectTV(_ tv: PanelTV) {
        host = tv.host
        remoteName = savedRemotes.first { $0.host == tv.host }?.name ?? tv.name
        notice = ""
    }

    public func selectRemote(_ remote: SavedRemote) {
        host = remote.host
        remoteName = remote.name
        connect()
    }

    public func editRemote(_ remote: SavedRemote) {
        showSettings()
        host = remote.host
        remoteName = remote.name
    }

    public func leaveSettings() {
        cancelDiscovery()
        settings = false
        if let active = savedRemotes.first(where: { $0.host == selectedRemoteHost }) {
            host = active.host
            remoteName = active.name
        } else {
            host = ""
            remoteName = ""
        }
        notice = ""
    }

    public func repairTV() {
        guard validateHost() else { return }
        onForget?()
        connect()
    }

    @discardableResult private func validateHost() -> Bool {
        host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard SavedRemotesStore.isValidHost(host) else {
            notice = "Enter a valid TV IPv4 address, such as 192.168.1.100."
            return false
        }
        return true
    }

    public func addRemote() {
        showSettings()
        host = ""
        remoteName = ""
    }

    public func showSettings() { confirmingPower = false; expanded = true; settings = true; notice = "" }
    public func cancelDiscovery() {
        discoveryTask?.cancel()
        discoveryTask = nil
        if discovering { discoveryNotice = "Search stopped. Find TVs to try again, or enter an IP." }
        discovering = false
    }

    public func close() {
        cancelDiscovery()
        if settings { leaveSettings() }
        confirmingPower = false; settings = false; expanded = false; notice = ""; controlQuery = ""
    }
}
