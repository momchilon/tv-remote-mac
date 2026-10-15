import XCTest

final class RemoteCheckTests: XCTestCase {
    func testDiagnosticAuthenticatesWithoutKeysOrCredentialOutput() throws {
        let fixture = try LocalTVFixture()
        defer { fixture.stop() }
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sibling = Bundle(for: RemoteCheckTests.self).bundleURL.deletingLastPathComponent().appendingPathComponent("RemoteCheck")
        let executable = FileManager.default.fileExists(atPath: sibling.path) ? sibling : package.appendingPathComponent(".build/debug/RemoteCheck")
        let process = Process()
        process.executableURL = executable
        process.arguments = ["--host", "127.0.0.1", "--timeout", "2"]
        var environment = ProcessInfo.processInfo.environment
        environment["REMOTEKIT_STORAGE_DIRECTORY"] = fixture.directory.appendingPathComponent("client").path
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let text = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)!
        XCTAssertEqual(process.terminationStatus, 0, text)
        XCTAssertTrue(text.contains("status: connected"), text)
        XCTAssertTrue(text.contains("authenticated: true"), text)
        XCTAssertFalse(text.contains("fixture-token"))
        XCTAssertFalse(text.contains("wss://"))
        XCTAssertEqual(try fixture.metrics()["keyMessages"] as? Int, 0)
        XCTAssertEqual(try fixture.metrics()["connections"] as? Int, 1)
    }
}
