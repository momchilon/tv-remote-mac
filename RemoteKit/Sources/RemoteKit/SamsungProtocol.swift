import Foundation
import CoreFoundation

struct LocalHost: Equatable, Sendable {
    let value: String

    init(_ input: String) throws {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4,
              parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) && ($0.count == 1 || $0.first != "0") }),
              parts.allSatisfy({ UInt8($0) != nil }) else { throw RemoteFailure.invalidHost }
        let octets = parts.map { UInt8($0)! }
        guard octets[0] == 10 ||
              (octets[0] == 172 && (16...31).contains(octets[1])) ||
              (octets[0] == 192 && octets[1] == 168) ||
              (octets[0] == 169 && octets[1] == 254) ||
              octets[0] == 127 else { throw RemoteFailure.invalidHost }
        self.value = value
    }
}

enum SamsungProtocol {
    enum ChannelEvent: Equatable {
        case connected(token: String?)
        case ignored
    }

    static func event(from text: String) throws -> ChannelEvent {
        guard let bytes = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let event = object["event"] as? String else { throw RemoteFailure.malformedMessage }
        switch event {
        case "ms.channel.connect":
            let data = object["data"] as? [String: Any]
            let raw = data?["token"]
            let token: String?
            if let string = raw as? String { token = string.isEmpty ? nil : string }
            else if let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
                token = number.stringValue
            } else { token = nil }
            return .connected(token: token)
        case "ms.channel.unauthorized": throw RemoteFailure.unauthorized
        case "ms.channel.timeOut", "ms.channel.timeout": throw RemoteFailure.pairingTimeout
        case "ms.error", "ms.channel.error": throw RemoteFailure.televisionError
        default: return .ignored
        }
    }

    static func keyMessage(_ key: RemoteKey) -> String {
        let object: [String: Any] = ["method": "ms.remote.control", "params": [
            "Cmd": "Click", "DataOfCmd": key.rawValue, "Option": "false", "TypeOfRemote": "SendRemoteKey"
        ]]
        return String(data: try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), encoding: .utf8)!
    }

    static func connectionURL(host: LocalHost, clientName: String, token: String?) -> URL {
        var components = URLComponents()
        components.scheme = "wss"
        components.host = host.value
        components.port = 8002
        components.path = "/api/v2/channels/samsung.remote.control"
        var fields = [URLQueryItem(name: "name", value: Data(clientName.utf8).base64EncodedString())]
        if let token, !token.isEmpty { fields.append(URLQueryItem(name: "token", value: token)) }
        // '+' must be escaped too: some TV firmware decodes a query as form data.
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        components.percentEncodedQuery = fields.map {
            $0.name + "=" + ($0.value ?? "").addingPercentEncoding(withAllowedCharacters: allowed)!
        }.joined(separator: "&")
        return components.url!
    }
}

enum RemoteFailure: Error, LocalizedError, Equatable {
    case invalidHost
    case malformedMessage
    case unauthorized
    case pairingTimeout
    case televisionError
    case storage
    case certificateChanged
    case untrustedEndpoint
    case connection
    case invalidMAC
    case wakeFailed

    var errorDescription: String? {
        switch self {
        case .malformedMessage: return "The TV sent an invalid remote-control response. Disconnect and try again."
        case .unauthorized: return "TV approval was denied or the saved pairing expired. Allow this remote on the TV; if needed, forget this TV and pair again."
        case .pairingTimeout: return "TV approval timed out. Turn on the TV, choose Allow on its prompt, then connect again."
        case .televisionError: return "The TV rejected the connection. Check its External Device Manager permissions, then try connecting again."
        case .storage: return "Cannot safely read or save pairing data. Check the Notch Remote Application Support folder permissions; do not delete saved certificates unless you intend to re-pair."
        case .certificateChanged: return "The TV certificate changed. Connection blocked. Verify this is your TV, then forget it and re-pair explicitly."
        case .untrustedEndpoint: return "TLS authentication was not for the configured TV IPv4 address on port 8002. Connection blocked."
        case .connection: return "Connection to the TV ended or could not be established. Check that it is on and on the same local network, then connect again."
        case .invalidMAC: return "Enter a six-byte unicast MAC address, such as AA:BB:CC:DD:EE:10."
        case .wakeFailed: return "The wake packet could not be sent. Check the local network. UDP delivery does not verify that the TV is awake."
        case .invalidHost: return "Enter a private/local IPv4 address only, without a URL, path or port."
        }
    }
}
