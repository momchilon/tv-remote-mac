import Foundation
import CryptoKit

/// Per-connection TOFU candidate: only SamsungRemote persists it after authentication.
final class CertificatePolicy {
    private let host: LocalHost
    private let savedPin: String?
    private let lock = NSLock()
    private var observedPin: String?
    private var rejection: RemoteFailure?

    init(host: LocalHost, savedPin: String?) {
        self.host = host
        self.savedPin = savedPin
    }

    var candidatePin: String? {
        lock.lock(); defer { lock.unlock() }
        return observedPin
    }

    var failure: RemoteFailure? {
        lock.lock(); defer { lock.unlock() }
        return rejection
    }

    func evaluate(host challengeHost: String, port: Int, certificate: Data) throws {
        lock.lock(); defer { lock.unlock() }
        guard challengeHost == host.value, port == 8002, !certificate.isEmpty else {
            rejection = .untrustedEndpoint
            throw RemoteFailure.untrustedEndpoint
        }
        let pin = SHA256.hash(data: certificate).map { String(format: "%02x", $0) }.joined()
        if let expected = savedPin ?? observedPin, expected != pin {
            rejection = .certificateChanged
            throw RemoteFailure.certificateChanged
        }
        observedPin = pin
    }
}
