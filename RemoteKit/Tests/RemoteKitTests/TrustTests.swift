import XCTest
import CryptoKit
@testable import RemoteKit

final class TrustTests: XCTestCase {
    func testTOFUIsScopedToExactEndpointAndRejectsChangedLeaf() throws {
        let host = try LocalHost("192.168.1.100")
        let original = Data("first certificate fixture".utf8)
        let changed = Data("changed certificate fixture".utf8)
        let policy = CertificatePolicy(host: host, savedPin: nil)
        XCTAssertNil(policy.candidatePin)
        XCTAssertThrowsError(try policy.evaluate(host: "192.168.1.101", port: 8002, certificate: original))
        XCTAssertThrowsError(try policy.evaluate(host: host.value, port: 8001, certificate: original))
        XCTAssertThrowsError(try policy.evaluate(host: host.value, port: 8002, certificate: Data()))
        XCTAssertNil(policy.candidatePin)
        try policy.evaluate(host: host.value, port: 8002, certificate: original)
        let hash = SHA256.hash(data: original).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(policy.candidatePin, hash)
        try policy.evaluate(host: host.value, port: 8002, certificate: original)
        XCTAssertThrowsError(try policy.evaluate(host: host.value, port: 8002, certificate: changed)) { error in
            XCTAssertEqual(error as? RemoteFailure, .certificateChanged)
            XCTAssertTrue(error.localizedDescription.contains("re-pair"))
        }
        let pinned = CertificatePolicy(host: host, savedPin: hash)
        XCTAssertThrowsError(try pinned.evaluate(host: host.value, port: 8002, certificate: changed))
        try pinned.evaluate(host: host.value, port: 8002, certificate: original)
        XCTAssertEqual(pinned.candidatePin, hash)
    }
}
