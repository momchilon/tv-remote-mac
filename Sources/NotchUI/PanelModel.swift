import Foundation
import Combine

public enum PanelCommand: String, CaseIterable {
    case up = "KEY_UP", down = "KEY_DOWN", left = "KEY_LEFT", right = "KEY_RIGHT"
    case enter = "KEY_ENTER", back = "KEY_RETURN", home = "KEY_HOME"
    case volumeUp = "KEY_VOLUP", volumeDown = "KEY_VOLDOWN", mute = "KEY_MUTE"
    case source = "KEY_SOURCE", power = "KEY_POWER"
}

public enum PanelConnection: Equatable {
    case disconnected, connecting, approval, ready, failed(String)
}

@MainActor
public final class PanelModel: ObservableObject {
    @Published public var expanded = false
    @Published public var settings = false
    @Published public var confirmingPower = false
    @Published public var host = ""
    @Published public var canWake = false
    @Published public var notice = ""
    @Published public var connection: PanelConnection = .disconnected {
        didSet { if connection != .ready { confirmingPower = false } }
    }
    public var onCommand: ((PanelCommand) -> Void)?
    public var onConnect: ((String) -> Void)?
    public var onWake: (() -> Void)?
    public var onForget: (() -> Void)?
    public var onQuit: (() -> Void)?

    public init() {}
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
        let clean = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { notice = "Enter your TV’s local IP address."; return }
        host = clean
        notice = ""
        connection = .connecting
        settings = false
        onConnect?(clean)
    }

    public func showSettings() { confirmingPower = false; expanded = true; settings = true; notice = "" }
    public func close() { confirmingPower = false; settings = false; expanded = false; notice = "" }
}
