import Foundation
import Darwin

/// Unauthenticated discovery hints only; connecting still requires normal TLS pairing.
public struct DiscoveredTV: Equatable, Sendable {
    public let host: String
    public let name: String
    public let model: String
    public let macAddress: String?

    public init(host: String, name: String, model: String, macAddress: String? = nil) {
        self.host = host
        self.name = name
        self.model = model
        self.macAddress = macAddress
    }
}

public struct TVDiscovery: Sendable {
    private let destinationHost: String
    private let destinationPort: UInt16
    private let httpPort: UInt16
    private let searchDuration: TimeInterval
    private let requestTimeout: TimeInterval

    public init() {
        self.init(destinationHost: "239.255.255.250", destinationPort: 1900,
                  httpPort: 8001, searchDuration: 2.5, requestTimeout: 1.25)
    }

    // Loopback-only test fixtures can substitute ports without changing the public API.
    init(destinationHost: String, destinationPort: UInt16, httpPort: UInt16,
         searchDuration: TimeInterval, requestTimeout: TimeInterval) {
        self.destinationHost = destinationHost
        self.destinationPort = destinationPort
        self.httpPort = httpPort
        self.searchDuration = searchDuration
        self.requestTimeout = requestTimeout
    }

    /// One bounded search; cancellation throws CancellationError and closes owned resources.
    public func discover() async throws -> [DiscoveredTV] {
        let search = Task.detached { try self.collectHosts() }
        let hosts = try await withTaskCancellationHandler {
            try await search.value
        } onCancel: {
            search.cancel()
        }
        try Task.checkCancellation()
        return try await withThrowingTaskGroup(of: DiscoveredTV?.self) { group in
            for host in hosts {
                group.addTask { try await self.probe(host) }
            }
            var results: [DiscoveredTV] = []
            for try await result in group {
                if let result { results.append(result) }
            }
            try Task.checkCancellation()
            return results.sorted { $0.host < $1.host }
        }
    }

    private func collectHosts() throws -> [String] {
        try Task.checkCancellation()
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { Darwin.close(fd) }
        guard fcntl(fd, F_SETFL, O_NONBLOCK) == 0 else { throw POSIXError(.EIO) }
        var destination = sockaddr_in()
        destination.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        destination.sin_family = sa_family_t(AF_INET)
        destination.sin_port = destinationPort.bigEndian
        guard inet_pton(AF_INET, destinationHost, &destination.sin_addr) == 1 else { throw RemoteFailure.invalidHost }
        let message = Data("M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 1\r\nST: ssdp:all\r\n\r\n".utf8)
        // Select each LAN interface explicitly so a VPN's default route cannot steal M-SEARCH.
        // Loopback fixtures bypass enumeration and never emit LAN traffic.
        let interfaces = destinationHost == "239.255.255.250" ? Self.multicastInterfaces() : []
        var sent = false
        for interface in interfaces.isEmpty ? [nil] : interfaces.map(Optional.some) {
            try Task.checkCancellation()
            if var interface {
                guard setsockopt(fd, IPPROTO_IP, IP_MULTICAST_IF, &interface, socklen_t(MemoryLayout<in_addr>.size)) == 0 else { continue }
            }
            let count = message.withUnsafeBytes { bytes in
                withUnsafePointer(to: &destination) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        sendto(fd, bytes.baseAddress, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
            if count == message.count { sent = true }
        }
        guard sent else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let deadline = ProcessInfo.processInfo.systemUptime + searchDuration
        var hosts = Set<String>()
        var buffer = [UInt8](repeating: 0, count: 8193)
        while ProcessInfo.processInfo.systemUptime < deadline {
            try Task.checkCancellation()
            var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, 25)
            if ready < 0 {
                if errno == EINTR { continue }
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            guard ready > 0, descriptor.revents & Int16(POLLIN) != 0 else { continue }
            var sender = sockaddr_in()
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            let count = withUnsafeMutablePointer(to: &sender) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    recvfrom(fd, &buffer, buffer.count, 0, $0, &length)
                }
            }
            guard count > 0, count <= 8192, sender.sin_family == sa_family_t(AF_INET) else { continue }
            var address = sender.sin_addr
            var text = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            guard inet_ntop(AF_INET, &address, &text, socklen_t(text.count)) != nil else { continue }
            let host = String(cString: text)
            guard let candidate = Self.parseSSDP(Data(buffer.prefix(count)), sender: host) else { continue }
            hosts.insert(candidate)
            if hosts.count >= 32 { break }
        }
        try Task.checkCancellation()
        return hosts.sorted()
    }

    static func isDiscoveryInterface(flags: UInt32, host: String) -> Bool {
        let required = UInt32(IFF_UP | IFF_RUNNING | IFF_MULTICAST)
        return flags & required == required && flags & UInt32(IFF_LOOPBACK | IFF_POINTOPOINT) == 0 &&
            (try? LocalHost(host)) != nil && !host.hasPrefix("127.")
    }

    private static func multicastInterfaces() -> [in_addr] {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0 else { return [] }
        defer { freeifaddrs(first) }
        var result: [in_addr] = []
        var seen = Set<UInt32>()
        var next = first
        while let current = next {
            defer { next = current.pointee.ifa_next }
            guard let address = current.pointee.ifa_addr,
                  address.pointee.sa_family == sa_family_t(AF_INET) else { continue }
            var ip = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
            var text = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            guard inet_ntop(AF_INET, &ip, &text, socklen_t(text.count)) != nil,
                  isDiscoveryInterface(flags: current.pointee.ifa_flags, host: String(cString: text)),
                  seen.insert(ip.s_addr).inserted else { continue }
            result.append(ip)
        }
        return result
    }

    private func probe(_ host: String) async throws -> DiscoveredTV? {
        try Task.checkCancellation()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = requestTimeout
        config.timeoutIntervalForResource = requestTimeout
        config.waitsForConnectivity = false
        config.urlCache = nil
        config.urlCredentialStorage = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.connectionProxyDictionary = [:]
        let session = URLSession(configuration: config, delegate: DiscoveryHTTPPolicy(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let url = URL(string: "http://\(host):\(httpPort)/api/v2/")!
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: requestTimeout)
        request.httpMethod = "GET"
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  response.expectedContentLength <= 65_536 else { return nil }
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < 65_536 else { return nil }
                data.append(byte)
            }
            return Self.parseDevice(data, host: host)
        } catch {
            try Task.checkCancellation()
            return nil // An individual device may be asleep, unsupported, or unresponsive.
        }
    }

    /// Only the UDP peer becomes a candidate. LOCATION and all advertised URLs are ignored.
    static func parseSSDP(_ data: Data, sender: String) -> String? {
        guard data.count <= 8192, (try? LocalHost(sender)) != nil,
              let response = String(data: data, encoding: .utf8),
              let end = response.range(of: "\r\n\r\n") else { return nil }
        let lines = response[..<end.lowerBound].components(separatedBy: "\r\n")
        guard lines.first == "HTTP/1.1 200 OK" else { return nil }
        var fields: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { return nil }
            let key = String(line[..<colon]).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            // Header names are HTTP tokens (including BOOTID.UPNP.ORG); EXT is normally empty.
            let tokenPunctuation = "!#$%&'*+-.^_`|~".utf8
            guard !key.isEmpty, key.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || tokenPunctuation.contains($0) }),
                  !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                  fields[key] == nil else { return nil }
            fields[key] = value
        }
        guard let target = fields["st"], !target.isEmpty else { return nil }
        return sender
    }

    static func parseDevice(_ data: Data, host: String) -> DiscoveredTV? {
        guard data.count <= 65_536, (try? LocalHost(host)) != nil,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let device = object["device"] as? [String: Any],
              device["type"] as? String == "Samsung SmartTV",
              let name = displayText(device["name"]),
              let model = displayText(device["modelName"]) else { return nil }
        let mac = device["wifiMac"] as? String
        let validMAC = mac.flatMap { (try? WakeOnLAN.packet(macAddress: $0)) == nil ? nil : $0 }
        return DiscoveredTV(host: host, name: name, model: model, macAddress: validMAC)
    }

    private static func displayText(_ value: Any?) -> String? {
        guard let text = value as? String, text.utf8.count <= 256,
              !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || CharacterSet.illegalCharacters.contains($0) }) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Samsung often HTML-escapes inches in JSON names. Decode text, never render HTML.
        let decoded = [("&quot;", "\""), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&")]
            .reduce(trimmed) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
        return decoded.isEmpty ? nil : decoded
    }
}

// Internal for policy tests; no discovery request may use an HTTP auth challenge.
final class DiscoveryHTTPPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(.cancelAuthenticationChallenge, nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(.cancelAuthenticationChallenge, nil)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
