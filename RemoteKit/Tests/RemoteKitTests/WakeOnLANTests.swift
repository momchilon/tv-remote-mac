import XCTest
import Darwin
@testable import RemoteKit

final class WakeOnLANTests: XCTestCase {
    @MainActor
    func testWakeSends102ByteUnicastMagicPacketWithoutClaimingAuthentication() throws {
        let receiver = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        XCTAssertGreaterThanOrEqual(receiver, 0)
        defer { Darwin.close(receiver) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(receiver, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        XCTAssertEqual(bound, 0)
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(receiver, $0, &length) } }
        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        _ = setsockopt(receiver, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        try WakeOnLAN.send(macAddress: "AA:BB:CC:DD:EE:10", host: LocalHost("127.0.0.1"), port: UInt16(bigEndian: address.sin_port))
        var buffer = [UInt8](repeating: 0, count: 1024)
        let count = recv(receiver, &buffer, buffer.count, 0)
        XCTAssertEqual(count, 102)
        XCTAssertEqual(Array(buffer.prefix(6)), Array(repeating: 0xff, count: 6))
        let expected: [UInt8] = [0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0x10]
        for i in 0..<16 { XCTAssertEqual(Array(buffer[(6 + i * 6)..<(12 + i * 6)]), expected) }
        let remote = SamsungRemote()
        remote.wake(macAddress: "invalid", host: "127.0.0.1")
        XCTAssertFalse(remote.isConnected)
        XCTAssertEqual(remote.status, .failed(RemoteFailure.invalidMAC.localizedDescription))
        for mac in ["", "AA:BB:CC:DD:EE", "AA:BB:CC:DD:EE:GG", "00:00:00:00:00:00", "FF:FF:FF:FF:FF:FF", "01:00:00:00:00:01"] {
            XCTAssertThrowsError(try WakeOnLAN.packet(macAddress: mac))
        }
    }
}
