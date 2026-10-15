import Foundation
import XCTest

final class LocalTVFixture {
    let directory: URL
    let process = Process()

    init(scenario: String = "connect", directory: URL? = nil) throws {
        self.directory = directory ?? FileManager.default.temporaryDirectory.appendingPathComponent("RemoteKit-fixture-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let script = Bundle.module.url(forResource: "local_tv", withExtension: "py", subdirectory: "Fixtures")!
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [script.path, "--directory", self.directory.path, "--scenario", scenario]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? FileManager.default.removeItem(at: self.directory.appendingPathComponent("ready"))
        try process.run()
        let deadline = Date().addingTimeInterval(8)
        while !FileManager.default.fileExists(atPath: self.directory.appendingPathComponent("ready").path) {
            guard process.isRunning, Date() < deadline else {
                if process.isRunning { process.terminate(); process.waitUntilExit() }
                throw NSError(domain: "Fixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Local TLS fixture could not bind loopback port 8002 or generate its certificate."])
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
    }

    func stop(removeFiles: Bool = true) {
        if process.isRunning { process.terminate(); process.waitUntilExit() }
        if removeFiles, FileManager.default.fileExists(atPath: directory.path) { try? FileManager.default.removeItem(at: directory) }
    }

    deinit { stop() }

    func metrics() throws -> [String: Any] {
        let data = try Data(contentsOf: directory.appendingPathComponent("metrics.json"))
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }
}
