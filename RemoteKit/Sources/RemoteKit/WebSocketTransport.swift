import Foundation
import Security

@MainActor
protocol RemoteTransport: AnyObject {
    var certificatePin: String? { get }
    func open(url: URL) async throws
    func receive() async throws -> String
    func send(text: String) async throws
    func ping() async throws
    func cancel()
}

/// A dedicated, ephemeral URLSession. Its trust exception cannot escape this TV endpoint.
@MainActor
final class NativeWebSocketTransport: RemoteTransport {
    private let host: LocalHost
    private let policy: CertificatePolicy
    private var session: URLSession?
    private var socket: URLSessionWebSocketTask?
    private var delegate: TVSessionDelegate?

    init(host: LocalHost, savedPin: String?) {
        self.host = host
        self.policy = CertificatePolicy(host: host, savedPin: savedPin)
    }

    var certificatePin: String? { policy.candidatePin }

    func open(url: URL) async throws {
        guard url.scheme == "wss", url.host == host.value, url.port == 8002,
              url.path == "/api/v2/channels/samsung.remote.control",
              url.user == nil, url.password == nil, url.fragment == nil else { throw RemoteFailure.untrustedEndpoint }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.connectionProxyDictionary = [:]
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 86_400
        configuration.waitsForConnectivity = false
        let delegate = TVSessionDelegate(policy: policy)
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: queue)
        let socket = session.webSocketTask(with: url)
        socket.maximumMessageSize = 65_536
        self.delegate = delegate
        self.session = session
        self.socket = socket
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                delegate.opening.wait(continuation)
                socket.resume()
            }
        }, onCancel: {
            socket.cancel(with: .goingAway, reason: nil)
            delegate.opening.finish(.failure(CancellationError()))
            session.invalidateAndCancel()
        })
    }

    func receive() async throws -> String {
        guard let socket else { throw RemoteFailure.connection }
        do {
            switch try await socket.receive() {
            case .string(let text): return text
            case .data(let data):
                guard let text = String(data: data, encoding: .utf8) else { throw RemoteFailure.malformedMessage }
                return text
            @unknown default: throw RemoteFailure.malformedMessage
            }
        } catch {
            throw policy.failure ?? (error as? RemoteFailure) ?? .connection
        }
    }

    func send(text: String) async throws {
        guard let socket else { throw RemoteFailure.connection }
        do { try await socket.send(.string(text)) }
        catch { throw policy.failure ?? .connection }
    }

    func ping() async throws {
        guard let socket else { throw RemoteFailure.connection }
        do {
            let completion = OpeningGate()
            try await withTaskCancellationHandler(operation: {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    completion.wait(continuation)
                    socket.sendPing { error in
                        completion.finish(error == nil ? .success(()) : .failure(RemoteFailure.connection))
                    }
                }
            }, onCancel: {
                completion.finish(.failure(CancellationError()))
                socket.cancel(with: .goingAway, reason: nil)
            })
        } catch { throw policy.failure ?? .connection }
    }

    func cancel() {
        delegate?.opening.finish(.failure(CancellationError()))
        socket?.cancel(with: .goingAway, reason: nil)
        session?.invalidateAndCancel()
        socket = nil
        session = nil
        delegate = nil
    }

    deinit {
        socket?.cancel(with: .goingAway, reason: nil)
        session?.invalidateAndCancel()
    }
}

/// The URLSession delegate runs on its private serial queue, not the main actor.
private final class TVSessionDelegate: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    let opening = OpeningGate()
    let policy: CertificatePolicy

    init(policy: CertificatePolicy) { self.policy = policy }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        authenticate(challenge, completionHandler: completionHandler)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        authenticate(challenge, completionHandler: completionHandler)
    }

    private func authenticate(_ challenge: URLAuthenticationChallenge,
                              completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let space = challenge.protectionSpace
        guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = space.serverTrust,
              let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let leaf = chain.first else {
            opening.finish(.failure(RemoteFailure.untrustedEndpoint))
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        do {
            try policy.evaluate(host: space.host, port: space.port, certificate: SecCertificateCopyData(leaf) as Data)
            completionHandler(.useCredential, URLCredential(trust: trust))
        } catch {
            opening.finish(.failure(error))
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Never forward a pairing token through a redirect, even to another local address.
        opening.finish(.failure(RemoteFailure.untrustedEndpoint))
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        opening.finish(.success(()))
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        opening.finish(.failure(RemoteFailure.connection))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        opening.finish(.failure(policy.failure ?? .connection))
    }
}

private final class OpeningGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var result: Result<Void, Error>?

    func wait(_ continuation: CheckedContinuation<Void, Error>) {
        lock.lock()
        if let result {
            lock.unlock()
            continuation.resume(with: result)
        } else {
            self.continuation = continuation
            lock.unlock()
        }
    }

    func finish(_ result: Result<Void, Error>) {
        lock.lock()
        guard self.result == nil else { lock.unlock(); return }
        self.result = result
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}
