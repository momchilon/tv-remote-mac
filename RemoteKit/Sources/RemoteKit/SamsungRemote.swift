import Foundation
import Combine

public enum RemoteStatus: Equatable {
    case disconnected
    case connecting
    case awaitingApproval
    case connected
    case failed(String)
}

struct RemoteTiming {
    var pairingTimeout: UInt64 = 45_000_000_000
    var pingInterval: UInt64 = 20_000_000_000
    var pingTimeout: UInt64 = 5_000_000_000
}

/// Local-network only, explicit-connect remote. A successful write is not a key acknowledgment.
@MainActor
public final class SamsungRemote: ObservableObject {
    @Published public private(set) var status: RemoteStatus = .disconnected
    public var isConnected: Bool { status == .connected }
    public var onDeviceInfo: ((String, String?) -> Void)?

    private let store: ConnectionStore
    private let timing: RemoteTiming
    private var pairingTask: Task<Void, Never>?
    private var keepaliveTask: Task<Void, Never>?
    private var pongDeadlineTask: Task<Void, Never>?
    private var transport: NativeWebSocketTransport?
    private var connectionTask: Task<Void, Never>?
    private var generation = UUID()
    private var activeHost: LocalHost?
    private var queuedKeys: [RemoteKey] = []
    private var sendingTask: Task<Void, Never>?
    private static let queueLimit = 12

    public convenience init(storageDirectory: URL? = nil) {
        self.init(storageDirectory: storageDirectory, timing: RemoteTiming())
    }

    init(storageDirectory: URL?, timing: RemoteTiming) {
        self.store = ConnectionStore(directory: storageDirectory)
        self.timing = timing
    }

    public func connect(host input: String) {
        disconnect()
        do {
            let host = try LocalHost(input)
            let record = try store.prepare(for: host)
            let transport = NativeWebSocketTransport(host: host, savedPin: record.certificateSHA256)
            let url = SamsungProtocol.connectionURL(host: host, clientName: record.clientName, token: record.token)
            let id = UUID()
            generation = id
            activeHost = host
            self.transport = transport
            status = .connecting
            let deadline = timing.pairingTimeout
            pairingTask = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: deadline) }
                catch { return }
                guard self?.generation == id, self?.isConnected == false else { return }
                self?.fail(RemoteFailure.pairingTimeout)
            }
            connectionTask = Task { [weak self] in
                var saved = record
                do {
                    try await transport.open(url: url)
                    guard !Task.isCancelled, self?.generation == id else { return }
                    self?.status = .awaitingApproval
                    while !Task.isCancelled {
                        let text = try await transport.receive()
                        guard !Task.isCancelled, self?.generation == id else { return }
                        switch try SamsungProtocol.event(from: text) {
                        case .connected(let token):
                            guard let pin = transport.certificatePin else { throw RemoteFailure.untrustedEndpoint }
                            if let token { saved.token = token }
                            saved.certificateSHA256 = pin
                            try self?.store.save(saved, for: host)
                            self?.pairingTask?.cancel()
                            self?.pairingTask = nil
                            self?.status = .connected
                            self?.startKeepalive(transport: transport, generation: id)
                        case .ignored: break
                        }
                    }
                } catch {
                    guard !Task.isCancelled, self?.generation == id else { return }
                    self?.fail(error)
                }
            }
        } catch { fail(error) }
    }

    private func startKeepalive(transport: NativeWebSocketTransport, generation id: UUID) {
        guard keepaliveTask == nil else { return }
        let interval = timing.pingInterval
        let timeout = timing.pingTimeout
        keepaliveTask = Task { [weak self] in
            do {
                while !Task.isCancelled {
                    try await Task.sleep(nanoseconds: interval)
                    guard self?.generation == id, self?.isConnected == true else { return }
                    self?.pongDeadlineTask = Task { [weak self] in
                        do { try await Task.sleep(nanoseconds: timeout) } catch { return }
                        guard self?.generation == id else { return }
                        self?.fail(RemoteFailure.connection)
                    }
                    try await transport.ping()
                    self?.pongDeadlineTask?.cancel()
                    self?.pongDeadlineTask = nil
                }
            } catch {
                guard !Task.isCancelled, self?.generation == id else { return }
                self?.fail(error)
            }
        }
    }

    public func send(_ key: RemoteKey) {
        guard isConnected, let transport, queuedKeys.count < Self.queueLimit else { return }
        queuedKeys.append(key)
        guard sendingTask == nil else { return }
        let id = generation
        sendingTask = Task { [weak self] in
            do {
                while !Task.isCancelled, let key = self?.takeNextKey(generation: id) {
                    try await transport.send(text: SamsungProtocol.keyMessage(key))
                    try await Task.sleep(nanoseconds: 250_000_000)
                }
                if self?.generation == id { self?.sendingTask = nil }
            } catch {
                guard !Task.isCancelled, self?.generation == id else { return }
                self?.fail(error)
            }
        }
    }

    private func takeNextKey(generation id: UUID) -> RemoteKey? {
        guard id == generation, isConnected, !queuedKeys.isEmpty else { return nil }
        return queuedKeys.removeFirst()
    }

    public func disconnect() {
        stopConnection()
        status = .disconnected
    }

    /// Sends one UDP magic packet to the specified TV. Does not connect or verify wake-up.
    public func wake(macAddress: String, host: String) {
        do { try WakeOnLAN.send(macAddress: macAddress, host: LocalHost(host)) }
        catch { fail(error) }
    }

    public func forget(host input: String) {
        do {
            let host = try LocalHost(input)
            if host == activeHost { disconnect() }
            try store.forget(host: host)
        } catch { fail(error) }
    }

    private func stopConnection() {
        generation = UUID()
        keepaliveTask?.cancel()
        keepaliveTask = nil
        pongDeadlineTask?.cancel()
        pongDeadlineTask = nil
        pairingTask?.cancel()
        pairingTask = nil
        sendingTask?.cancel()
        sendingTask = nil
        queuedKeys.removeAll()
        connectionTask?.cancel()
        connectionTask = nil
        transport?.cancel()
        transport = nil
        activeHost = nil
    }

    private func fail(_ error: Error) {
        stopConnection()
        // Never surface NSError.userInfo, payloads or failing URLs (which can contain tokens).
        status = .failed(((error as? RemoteFailure) ?? .connection).localizedDescription)
    }

    deinit { connectionTask?.cancel(); sendingTask?.cancel(); pairingTask?.cancel(); keepaliveTask?.cancel(); pongDeadlineTask?.cancel() }
}
