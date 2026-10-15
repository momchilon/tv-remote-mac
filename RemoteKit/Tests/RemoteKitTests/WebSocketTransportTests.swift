import XCTest
@testable import RemoteKit

final class WebSocketTransportTests: XCTestCase {
    @MainActor
    func testNativeTLSWebSocketReceivesConnectAndKeepaliveWithoutSendingKeys() async throws {
        let fixture = try LocalTVFixture()
        defer { fixture.stop() }
        let host = try LocalHost("127.0.0.1")
        let transport = NativeWebSocketTransport(host: host, savedPin: nil)
        defer { transport.cancel() }
        let url = SamsungProtocol.connectionURL(host: host, clientName: "Fixture Remote", token: nil)
        try await transport.open(url: url)
        let event = try SamsungProtocol.event(from: await transport.receive())
        XCTAssertEqual(event, .connected(token: "fixture-token"))
        XCTAssertEqual(transport.certificatePin?.count, 64)
        // URLSession processes control frames while the receive loop is active.
        let receiving = Task { try await transport.receive() }
        defer { receiving.cancel() }
        try await transport.ping()
        let metrics = try fixture.metrics()
        XCTAssertEqual(metrics["connections"] as? Int, 1)
        XCTAssertEqual(metrics["keyMessages"] as? Int, 0)
        XCTAssertEqual(metrics["pings"] as? Int, 1)
    }
}
