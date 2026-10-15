import XCTest
import Combine
@testable import RemoteKit

@MainActor
func eventually(timeout: TimeInterval = 3, _ predicate: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !predicate(), Date() < deadline { try? await Task.sleep(nanoseconds: 10_000_000) }
    return predicate()
}

final class SamsungRemoteTests: XCTestCase {
    @MainActor
    func testConnectedRemoteSendsKeepaliveAndStopsItOnDisconnect() async throws {
        let fixture = try LocalTVFixture()
        defer { fixture.stop() }
        let remote = SamsungRemote(storageDirectory: fixture.directory.appendingPathComponent("client"), timing: RemoteTiming(pingInterval: 50_000_000))
        defer { remote.disconnect() }
        remote.connect(host: "127.0.0.1")
        let connected = await eventually { remote.isConnected }
        XCTAssertTrue(connected)
        let pinged = await eventually { (try? fixture.metrics()["pings"] as? Int ?? 0) ?? 0 >= 2 }
        XCTAssertTrue(pinged)
        remote.disconnect()
        let count = try fixture.metrics()["pings"] as? Int
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(try fixture.metrics()["pings"] as? Int, count)
        XCTAssertEqual(remote.status, .disconnected)
    }

    @MainActor
    func testPairingDeadlineFailsOnceWithoutPinningOrAutomaticReconnect() async throws {
        let fixture = try LocalTVFixture(scenario: "silent")
        defer { fixture.stop() }
        let storage = fixture.directory.appendingPathComponent("client")
        let remote = SamsungRemote(storageDirectory: storage, timing: RemoteTiming(pairingTimeout: 200_000_000))
        defer { remote.disconnect() }
        remote.connect(host: "127.0.0.1")
        let timedOut = await eventually { if case .failed = remote.status { return true }; return false }
        XCTAssertTrue(timedOut)
        XCTAssertEqual(remote.status, .failed(RemoteFailure.pairingTimeout.localizedDescription))
        XCTAssertFalse(remote.isConnected)
        let record = try ConnectionStore(directory: storage).load(for: LocalHost("127.0.0.1"))
        XCTAssertNil(record.token)
        XCTAssertNil(record.certificateSHA256)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(try fixture.metrics()["connections"] as? Int, 1)
    }

    @MainActor
    func testKeysAreGatedSerializedAndCancelledOnDisconnect() async throws {
        let fixture = try LocalTVFixture(scenario: "delayed")
        defer { fixture.stop() }
        let remote = SamsungRemote(storageDirectory: fixture.directory.appendingPathComponent("client"))
        defer { remote.disconnect() }
        remote.send(.power) // Must not be transmitted before authentication.
        remote.connect(host: "127.0.0.1")
        let awaiting = await eventually { remote.status == .awaitingApproval }
        XCTAssertTrue(awaiting)
        remote.send(.mute) // Still gated.
        let connected = await eventually { remote.isConnected }
        XCTAssertTrue(connected)
        remote.send(.up)
        remote.send(.down)
        remote.send(.enter)
        let sent = await eventually { (try? fixture.metrics()["keyMessages"] as? Int) == 3 }
        XCTAssertTrue(sent)
        let metrics = try fixture.metrics()
        XCTAssertEqual(metrics["keys"] as? [String], ["KEY_UP", "KEY_DOWN", "KEY_ENTER"])
        let times = metrics["keyTimes"] as! [Double]
        XCTAssertGreaterThanOrEqual(times[1] - times[0], 0.20)
        XCTAssertGreaterThanOrEqual(times[2] - times[1], 0.20)
        for _ in 0..<30 { remote.send(.left) }
        remote.disconnect()
        remote.send(.home)
        try await Task.sleep(nanoseconds: 350_000_000)
        XCTAssertEqual(try fixture.metrics()["keyMessages"] as? Int, 3)
    }

    @MainActor
    func testConnectRequiresChannelApprovalBeforeControlsAndDurablePin() async throws {
        let fixture = try LocalTVFixture(scenario: "delayed")
        defer { fixture.stop() }
        let storage = fixture.directory.appendingPathComponent("client")
        let remote = SamsungRemote(storageDirectory: storage)
        defer { remote.disconnect() }
        let host = try LocalHost("127.0.0.1")
        var statuses: [RemoteStatus] = []
        let subscription = remote.$status.sink { statuses.append($0) }
        defer { subscription.cancel() }
        XCTAssertEqual(remote.status, .disconnected)
        remote.connect(host: "127.0.0.1")
        XCTAssertEqual(remote.status, .connecting)
        XCTAssertFalse(remote.isConnected)
        let awaiting = await eventually { remote.status == .awaitingApproval }
        XCTAssertTrue(awaiting)
        XCTAssertNil(try ConnectionStore(directory: storage).load(for: host).certificateSHA256)
        XCTAssertNil(try ConnectionStore(directory: storage).load(for: host).token)
        let connected = await eventually { remote.isConnected }
        XCTAssertTrue(connected)
        let record = try ConnectionStore(directory: storage).load(for: host)
        XCTAssertEqual(record.token, "fixture-token")
        XCTAssertEqual(record.certificateSHA256?.count, 64)
        XCTAssertEqual(statuses, [.disconnected, .disconnected, .connecting, .awaitingApproval, .connected])
        XCTAssertEqual(try fixture.metrics()["keyMessages"] as? Int, 0)
        remote.disconnect()
        XCTAssertEqual(remote.status, .disconnected)
        XCTAssertFalse(remote.isConnected)
    }
}
