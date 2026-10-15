import Foundation
import Darwin

struct SavedConnection: Codable, Equatable {
    var token: String?
    var clientName: String
    var certificateSHA256: String?
    // Retained for compatibility with existing saved records; no imports are performed.
    var legacyImportAttempted = false

    static let fresh = SavedConnection(token: nil, clientName: "Notch Remote", certificateSHA256: nil)
}

/// Contains secrets. Never include records, URLs or underlying errors in logs.
final class ConnectionStore {
    let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Notch Remote", isDirectory: true)
    }

    func load(for host: LocalHost) throws -> SavedConnection {
        try readAll()[host.value] ?? .fresh
    }

    func prepare(for host: LocalHost) throws -> SavedConnection {
        try load(for: host)
    }

    func forget(host: LocalHost) throws {
        try save(.fresh, for: host)
    }

    func save(_ connection: SavedConnection, for host: LocalHost) throws {
        do {
            guard let directoryFD = try openDirectory(create: true) else { throw RemoteFailure.storage }
            defer { Darwin.close(directoryFD) }
            // Keep this inode permanently: unlinking it could split writers across different locks.
            let lockDescriptor = openat(directoryFD, ".connections.lock", O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
            guard lockDescriptor >= 0 else { throw RemoteFailure.storage }
            defer { flock(lockDescriptor, LOCK_UN); Darwin.close(lockDescriptor) }
            var metadata = stat()
            guard fstat(lockDescriptor, &metadata) == 0,
                  metadata.st_mode & S_IFMT == S_IFREG,
                  metadata.st_uid == getuid(), metadata.st_nlink == 1,
                  fchmod(lockDescriptor, 0o600) == 0 else { throw RemoteFailure.storage }
            while flock(lockDescriptor, LOCK_EX) != 0 {
                guard errno == EINTR else { throw RemoteFailure.storage }
            }
            var records = try readAll()
            records[host.value] = connection
            let bytes = try JSONEncoder().encode(records)
            let temporary = ".connections-" + UUID().uuidString
            let descriptor = openat(directoryFD, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
            guard descriptor >= 0 else { throw RemoteFailure.storage }
            defer { Darwin.close(descriptor); unlinkat(directoryFD, temporary, 0) }
            guard fchmod(descriptor, 0o600) == 0 else { throw RemoteFailure.storage }
            try bytes.withUnsafeBytes { raw in
                var offset = 0
                while offset < raw.count {
                    let count = Darwin.write(descriptor, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                    if count < 0 && errno == EINTR { continue }
                    guard count > 0 else { throw RemoteFailure.storage }
                    offset += count
                }
            }
            guard fsync(descriptor) == 0,
                  renameat(directoryFD, temporary, directoryFD, "connections.json") == 0,
                  fsync(directoryFD) == 0 else { throw RemoteFailure.storage }
        } catch { throw RemoteFailure.storage }
    }

    private func openDirectory(create: Bool) throws -> Int32? {
        var metadata = stat()
        if lstat(directory.path, &metadata) != 0 {
            guard errno == ENOENT else { throw RemoteFailure.storage }
            if !create { return nil }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        }
        let descriptor = Darwin.open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw RemoteFailure.storage }
        guard fstat(descriptor, &metadata) == 0, metadata.st_uid == getuid(),
              fchmod(descriptor, 0o700) == 0 else {
            Darwin.close(descriptor)
            throw RemoteFailure.storage
        }
        return descriptor
    }

    private func readAll() throws -> [String: SavedConnection] {
        do {
            guard let directoryFD = try openDirectory(create: false) else { return [:] }
            defer { Darwin.close(directoryFD) }
            let descriptor = openat(directoryFD, "connections.json", O_RDONLY | O_NOFOLLOW)
            if descriptor < 0 {
                if errno == ENOENT { return [:] }
                throw RemoteFailure.storage
            }
            defer { Darwin.close(descriptor) }
            var metadata = stat()
            guard fstat(descriptor, &metadata) == 0,
                  metadata.st_mode & S_IFMT == S_IFREG,
                  metadata.st_uid == getuid(), metadata.st_nlink == 1,
                  metadata.st_size <= 1_048_576, fchmod(descriptor, 0o600) == 0 else { throw RemoteFailure.storage }
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
            let data = try handle.readToEnd() ?? Data()
            return try JSONDecoder().decode([String: SavedConnection].self, from: data)
        } catch { throw RemoteFailure.storage }
    }
}
