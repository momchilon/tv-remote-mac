import Foundation
import Darwin

/// Best-effort local unicast. UDP submission is not proof that the TV woke.
enum WakeOnLAN {
    static func packet(macAddress input: String) throws -> Data {
        let mac = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let separator: Character = mac.contains(":") ? ":" : "-"
        let parts = mac.split(separator: separator, omittingEmptySubsequences: false)
        guard parts.count == 6, parts.allSatisfy({ $0.count == 2 && $0.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) }) else { throw RemoteFailure.invalidMAC }
        let bytes = parts.compactMap { UInt8($0, radix: 16) }
        guard bytes.count == 6, bytes[0] & 1 == 0, bytes.contains(where: { $0 != 0 }) else { throw RemoteFailure.invalidMAC }
        return Data(Array(repeating: UInt8(0xff), count: 6) + Array(repeating: bytes, count: 16).flatMap { $0 })
    }

    static func send(macAddress: String, host: LocalHost, port: UInt16 = 9) throws {
        let bytes = try packet(macAddress: macAddress)
        let descriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard descriptor >= 0 else { throw RemoteFailure.wakeFailed }
        defer { Darwin.close(descriptor) }
        var destination = sockaddr_in()
        destination.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        destination.sin_family = sa_family_t(AF_INET)
        destination.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host.value, &destination.sin_addr) == 1 else { throw RemoteFailure.invalidHost }
        let count = bytes.withUnsafeBytes { raw in
            withUnsafePointer(to: &destination) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(descriptor, raw.baseAddress, raw.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard count == bytes.count else { throw RemoteFailure.wakeFailed }
    }
}
