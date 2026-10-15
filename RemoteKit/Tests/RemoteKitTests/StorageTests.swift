import XCTest
import Darwin
@testable import RemoteKit

final class StorageTests: XCTestCase {
    func testSaveWaitsForCrossProcessLockBeforeReadingAndPreservesDifferentHosts() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("RemoteKit-lock-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let peer = Process()
        let release = Pipe()
        peer.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        peer.arguments = ["-c", """
        import fcntl, json, os, pathlib, sys
        directory = pathlib.Path(sys.argv[1])
        descriptor = os.open(directory / '.connections.lock', os.O_CREAT | os.O_RDWR, 0o600)
        fcntl.flock(descriptor, fcntl.LOCK_EX)
        path = directory / 'connections.json'
        records = json.loads(path.read_text()) if path.exists() else {}
        (directory / 'peer-ready').touch()
        sys.stdin.buffer.read(1)
        records['10.1.2.10'] = {'token': 'peer-token', 'clientName': 'Peer',
                                'certificateSHA256': None, 'legacyImportAttempted': False}
        temporary = directory / '.peer-connections'
        with open(os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'w') as output:
            json.dump(records, output)
        os.replace(temporary, path)
        fcntl.flock(descriptor, fcntl.LOCK_UN)
        os.close(descriptor)
        """, directory.path]
        peer.standardInput = release
        peer.standardOutput = FileHandle.nullDevice
        peer.standardError = FileHandle.nullDevice
        try peer.run()
        defer {
            try? release.fileHandleForWriting.close()
            if peer.isRunning { peer.terminate(); peer.waitUntilExit() }
        }
        let deadline = Date().addingTimeInterval(5)
        while !FileManager.default.fileExists(atPath: directory.appendingPathComponent("peer-ready").path) {
            guard peer.isRunning, Date() < deadline else {
                XCTFail("Independent writer did not acquire the shared lock")
                return
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        let started = DispatchSemaphore(value: 0)
        let completed = DispatchSemaphore(value: 0)
        let writers = DispatchGroup()
        let hosts = try ["10.1.2.11", "10.1.2.12", "10.1.2.13"].map(LocalHost.init)
        for host in hosts {
            writers.enter()
            DispatchQueue.global().async {
                defer { completed.signal(); writers.leave() }
                started.signal()
                let connection = SavedConnection(token: host.value, clientName: "Swift writer", certificateSHA256: nil)
                do { try ConnectionStore(directory: directory).save(connection, for: host) }
                catch { XCTFail("Saving fixture credentials failed") }
            }
        }
        for _ in hosts { XCTAssertEqual(started.wait(timeout: .now() + 5), .success) }
        XCTAssertEqual(completed.wait(timeout: .now() + 0.25), .timedOut,
                       "Saving must wait for the independent process's lock before reading records")
        try release.fileHandleForWriting.write(contentsOf: Data([1]))
        try release.fileHandleForWriting.close()
        peer.waitUntilExit()
        XCTAssertEqual(peer.terminationStatus, 0)
        XCTAssertEqual(writers.wait(timeout: .now() + 5), .success)
        let store = ConnectionStore(directory: directory)
        XCTAssertEqual(try store.load(for: LocalHost("10.1.2.10")).token, "peer-token")
        for host in hosts { XCTAssertEqual(try store.load(for: host).token, host.value) }
    }

    func testPrepareDoesNotImportUnrelatedCredentialsAndForgetDoesNotResurrect() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("RemoteKit-import-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let legacy = base.appendingPathComponent("legacy.token")
        try Data("fixture-token\n".utf8).write(to: legacy)
        let store = ConnectionStore(directory: base.appendingPathComponent("new"))
        let target = try LocalHost("192.168.1.100")
        let other = try LocalHost("192.168.1.101")
        XCTAssertEqual(try store.prepare(for: other), .fresh)
        XCTAssertEqual(try store.prepare(for: target), .fresh)
        XCTAssertEqual(try store.load(for: target), .fresh)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.directory.path))
        let saved = SavedConnection(token: "new-token", clientName: "Paired Client", certificateSHA256: "pin")
        try store.save(saved, for: target)
        XCTAssertEqual(try store.prepare(for: target), saved)
        try store.forget(host: target)
        XCTAssertEqual(try store.prepare(for: target), .fresh)
        XCTAssertEqual(try ConnectionStore(directory: store.directory).prepare(for: target), .fresh)
        XCTAssertEqual(try String(contentsOf: legacy), "fixture-token\n")
    }

    func testPreparingExistingCredentialsPreservesSavedFieldsAndFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("RemoteKit-existing-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let host = try LocalHost("192.168.1.100")
        let file = directory.appendingPathComponent("connections.json")
        let bytes = Data("""
        {"192.168.1.100":{"token":"saved-test-token","clientName":"Previously Paired Client","certificateSHA256":"saved-test-pin","legacyImportAttempted":true}}
        """.utf8)
        try bytes.write(to: file)
        let saved = try ConnectionStore(directory: directory).prepare(for: host)
        XCTAssertEqual(saved.token, "saved-test-token")
        XCTAssertEqual(saved.clientName, "Previously Paired Client")
        XCTAssertEqual(saved.certificateSHA256, "saved-test-pin")
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }

    func testStoreRefusesSymlinkedDirectoryOrCredentialFile() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("RemoteKit-symlink-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let actual = base.appendingPathComponent("actual")
        let alias = base.appendingPathComponent("alias")
        let host = try LocalHost("10.1.2.3")
        try ConnectionStore(directory: actual).save(.fresh, for: host)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: actual)
        XCTAssertThrowsError(try ConnectionStore(directory: alias).load(for: host))
        XCTAssertThrowsError(try ConnectionStore(directory: alias).save(.fresh, for: host))
        let secret = actual.appendingPathComponent("connections.json")
        let linked = actual.appendingPathComponent("outside.json")
        try FileManager.default.moveItem(at: secret, to: linked)
        try FileManager.default.createSymbolicLink(at: secret, withDestinationURL: linked)
        XCTAssertThrowsError(try ConnectionStore(directory: actual).load(for: host))
        XCTAssertThrowsError(try ConnectionStore(directory: actual).save(.fresh, for: host))
    }

    func testStoreRefusesSymlinkedHardLinkedOrNonRegularLockFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("RemoteKit-lock-file-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let lock = directory.appendingPathComponent(".connections.lock")
        let outside = directory.appendingPathComponent("outside")
        let bytes = Data("untouched".utf8)
        try bytes.write(to: outside)
        let store = ConnectionStore(directory: directory)
        let host = try LocalHost("10.1.2.3")
        try FileManager.default.createSymbolicLink(at: lock, withDestinationURL: outside)
        XCTAssertThrowsError(try store.save(.fresh, for: host))
        XCTAssertEqual(try Data(contentsOf: outside), bytes)
        try FileManager.default.removeItem(at: lock)
        try FileManager.default.linkItem(at: outside, to: lock)
        XCTAssertThrowsError(try store.save(.fresh, for: host))
        XCTAssertEqual(try Data(contentsOf: outside), bytes)
        try FileManager.default.removeItem(at: lock)
        try FileManager.default.createDirectory(at: lock, withIntermediateDirectories: false)
        XCTAssertThrowsError(try store.save(.fresh, for: host))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("connections.json").path))
    }

    func testHostScopedCredentialsRoundTripWithPrivatePermissions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("RemoteKit-store-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let host = try LocalHost("192.168.1.100")
        let other = try LocalHost("10.2.3.4")
        let store = ConnectionStore(directory: directory)
        let first = SavedConnection(token: "test-only-secret", clientName: "Notch Remote", certificateSHA256: String(repeating: "a", count: 64))
        try store.save(first, for: host)
        let lock = directory.appendingPathComponent(".connections.lock")
        var originalLock = stat()
        XCTAssertEqual(lstat(lock.path, &originalLock), 0)
        try store.save(SavedConnection(token: "other", clientName: "other", certificateSHA256: nil), for: other)
        var savedLock = stat()
        XCTAssertEqual(lstat(lock.path, &savedLock), 0)
        XCTAssertEqual(savedLock.st_ino, originalLock.st_ino, "Every save must use the same permanent lock inode")
        XCTAssertEqual(savedLock.st_mode & S_IFMT, S_IFREG)
        XCTAssertEqual(savedLock.st_mode & 0o777, 0o600)
        XCTAssertEqual(savedLock.st_uid, getuid())
        XCTAssertEqual(savedLock.st_nlink, 1)
        XCTAssertEqual(try ConnectionStore(directory: directory).load(for: host), first)
        XCTAssertEqual(try store.load(for: other).token, "other")
        let dirMode = try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as! NSNumber
        let fileMode = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("connections.json").path)[.posixPermissions] as! NSNumber
        XCTAssertEqual(dirMode.intValue, 0o700)
        XCTAssertEqual(fileMode.intValue, 0o600)
    }
}
