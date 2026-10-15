import Foundation

public struct SavedRemote: Codable, Equatable, Identifiable, Sendable {
    public let host: String
    public var name: String
    public var id: String { host }
    public var displayLabel: String { name == host ? host : "\(name) · \(host)" }

    public init(host: String, name: String) {
        self.host = host
        self.name = name
    }
}

@MainActor
public final class SavedRemotesStore {
    private let defaults: UserDefaults
    public private(set) var remotes: [SavedRemote] = []
    public private(set) var selectedHost: String = ""

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: "savedRemotes"),
           let saved = try? JSONDecoder().decode([SavedRemote].self, from: data) {
            remotes = saved
        }
        selectedHost = defaults.string(forKey: "tvHost") ?? ""
        if defaults.data(forKey: "savedRemotes") == nil {
            if save(host: selectedHost, name: selectedHost) == nil {
                selectedHost = ""
                defaults.removeObject(forKey: "tvHost")
            }
        }
    }

    public func select(host: String) {
        guard remotes.contains(where: { $0.host == host }) else { return }
        selectedHost = host
        defaults.set(host, forKey: "tvHost")
    }

    public func remove(host: String) {
        remotes.removeAll { $0.host == host }
        if selectedHost == host {
            selectedHost = remotes.first?.host ?? ""
        }
        persist()
    }

    private func persist() {
        defaults.set(try? JSONEncoder().encode(remotes), forKey: "savedRemotes")
        if selectedHost.isEmpty {
            defaults.removeObject(forKey: "tvHost")
        } else {
            defaults.set(selectedHost, forKey: "tvHost")
        }
    }

    public static func isValidHost(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4,
              parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } && ($0.count == 1 || $0.first != "0") }),
              parts.allSatisfy({ UInt8($0) != nil }) else { return false }
        let octets = parts.map { UInt8($0)! }
        // Match the backend's local IPv4 scope, excluding its test-only loopback use.
        return octets[0] == 10 ||
            (octets[0] == 172 && (16...31).contains(octets[1])) ||
            (octets[0] == 192 && octets[1] == 168) ||
            (octets[0] == 169 && octets[1] == 254)
    }

    @discardableResult
    public func save(host: String, name: String) -> SavedRemote? {
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidHost(host) else { return nil }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let remote = SavedRemote(host: host, name: name.isEmpty ? host : name)
        if let index = remotes.firstIndex(where: { $0.host == host }) {
            remotes[index] = remote
        } else {
            remotes.append(remote)
        }
        selectedHost = host
        persist()
        return remote
    }
}
