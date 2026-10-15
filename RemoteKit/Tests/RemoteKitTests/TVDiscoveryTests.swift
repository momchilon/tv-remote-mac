import XCTest
import Darwin
@testable import RemoteKit

final class TVDiscoveryTests: XCTestCase {
    func testSSDPAllowsEmptyExtensionAndDottedHeaderNamesUsedByRealSamsungTVs() {
        let packet = "HTTP/1.1 200 OK\r\nCACHE-CONTROL: max-age=1800\r\nEXT:\r\nLOCATION: http://192.168.1.42:9197/dmr\r\nSERVER: Samsung UPnP/1.0\r\nST: urn:schemas-upnp-org:device:MediaRenderer:1\r\nUSN: uuid:fixture-only\r\nContent-Length: 0\r\nBOOTID.UPNP.ORG: 1\r\n\r\n"
        XCTAssertEqual(TVDiscovery.parseSSDP(Data(packet.utf8), sender: "192.168.1.42"), "192.168.1.42")
    }

    func testSamsungNamesDecodeCommonEscapesWithoutInterpretingMarkup() {
        let data = Data(#"{"device":{"type":"Samsung SmartTV","name":"65&quot; Crystal &amp; UHD","modelName":"QN-Test"}}"#.utf8)
        XCTAssertEqual(TVDiscovery.parseDevice(data, host: "192.168.1.42")?.name, "65\" Crystal & UHD")
        let escapedTwice = Data(#"{"device":{"type":"Samsung SmartTV","name":"TV &amp;quot;","modelName":"QN-Test"}}"#.utf8)
        XCTAssertEqual(TVDiscovery.parseDevice(escapedTwice, host: "192.168.1.42")?.name, "TV &quot;")
    }

    func testRejectsUntrustedMalformedOrOversizedMetadata() {
        for json in [
            #"{"device":{"type":"Other SmartTV","name":"TV","modelName":"X"}}"#,
            #"{"device":{"type":"Samsung SmartTV","name":"","modelName":"X"}}"#,
            #"{"device":{"type":"Samsung SmartTV","name":"TV\nFake","modelName":"X"}}"#,
            #"{"device":{"type":"Samsung SmartTV","name":"TV","modelName":4}}"#,
            "not json", "[]", String(repeating: "x", count: 65537)
        ] { XCTAssertNil(TVDiscovery.parseDevice(Data(json.utf8), host: "127.0.0.1"), json.prefix(100).description) }
        let valid = Data(#"{"device":{"type":"Samsung SmartTV","name":"TV","modelName":"X","wifiMac":"invalid"}}"#.utf8)
        XCTAssertNil(TVDiscovery.parseDevice(valid, host: "8.8.8.8"))
        XCTAssertNil(TVDiscovery.parseDevice(valid, host: "localhost"))
        XCTAssertNil(TVDiscovery.parseDevice(valid, host: "127.0.0.1")?.macAddress)
    }

    func testSSDPParserRejectsMalformedPacketsAndNonlocalSenders() {
        let packet = "HTTP/1.1 200 OK\r\nsT: upnp:rootdevice\r\nLOCATION: http://8.8.8.8/arbitrary\r\n\r\n"
        XCTAssertEqual(TVDiscovery.parseSSDP(Data(packet.utf8), sender: "192.168.1.42"), "192.168.1.42")
        XCTAssertNil(TVDiscovery.parseSSDP(Data(packet.utf8), sender: "8.8.8.8"))
        for invalid in ["", "NOTIFY * HTTP/1.1\r\nST: x\r\n\r\n", "HTTP/1.1 500 OK\r\nST: x\r\n\r\n",
                        "HTTP/1.1 200 OK\r\n\r\n", "HTTP/1.1 200 OK\r\nST: x\r\nBroken\r\n\r\n",
                        "HTTP/1.1 200 OK\r\nST: \r\n\r\n", "HTTP/1.1 200 OK\r\nST: x\r\nST: y\r\n\r\n",
                        packet + String(repeating: "x", count: 8193), packet.replacingOccurrences(of: "\r\n", with: "\n")] {
            XCTAssertNil(TVDiscovery.parseSSDP(Data(invalid.utf8), sender: "127.0.0.1"))
        }
        XCTAssertNil(TVDiscovery.parseSSDP(Data([0xff, 0xfe]), sender: "127.0.0.1"))
    }

    func testHTTPAuthenticationChallengesAreCancelledWithoutCredentials() {
        let policy = DiscoveryHTTPPolicy()
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: URL(string: "http://127.0.0.1:8001/api/v2/")!)
        let challenge = URLAuthenticationChallenge(
            protectionSpace: URLProtectionSpace(host: "127.0.0.1", port: 8001, protocol: "http", realm: "TV", authenticationMethod: NSURLAuthenticationMethodHTTPBasic),
            proposedCredential: URLCredential(user: "fixture-user", password: "fixture-only", persistence: .none),
            previousFailureCount: 0, failureResponse: nil, error: nil, sender: ChallengeSender())
        var completions = 0
        policy.urlSession(session, task: task, didReceive: challenge) { disposition, credential in
            XCTAssertEqual(disposition, .cancelAuthenticationChallenge)
            XCTAssertNil(credential)
            completions += 1
        }
        policy.urlSession(session, didReceive: challenge) { disposition, credential in
            XCTAssertEqual(disposition, .cancelAuthenticationChallenge)
            XCTAssertNil(credential)
            completions += 1
        }
        XCTAssertEqual(completions, 2)
    }

    func testOnlyActiveLocalMulticastInterfacesAreEligible() {
        let active = UInt32(IFF_UP | IFF_RUNNING | IFF_MULTICAST)
        XCTAssertTrue(TVDiscovery.isDiscoveryInterface(flags: active, host: "192.168.1.2"))
        for flags in [active & ~UInt32(IFF_UP), active & ~UInt32(IFF_RUNNING), active & ~UInt32(IFF_MULTICAST),
                      active | UInt32(IFF_LOOPBACK), active | UInt32(IFF_POINTOPOINT)] {
            XCTAssertFalse(TVDiscovery.isDiscoveryInterface(flags: flags, host: "192.168.1.2"))
        }
        for host in ["127.0.0.1", "8.8.8.8", "localhost", "::1"] {
            XCTAssertFalse(TVDiscovery.isDiscoveryInterface(flags: active, host: host))
        }
    }

    func testNonSamsungMalformedAndOversizedHTTPResponsesAreFiltered() async throws {
        for mode in ["other", "malformed", "oversized", "streamedOversized", "status"] {
            let fixture = try DiscoveryFixture(mode: mode)
            defer { fixture.stop() }
            let discovery = TVDiscovery(destinationHost: "127.0.0.1", destinationPort: fixture.udpPort,
                                        httpPort: fixture.httpPort, searchDuration: 0.05, requestTimeout: 0.5)
            let results = try await discovery.discover()
            XCTAssertTrue(results.isEmpty, mode)
            XCTAssertEqual(try fixture.requests().count, 1, mode)
        }
    }

    func testCancellationDuringUDPWaitIsResponsive() async throws {
        let fixture = try DiscoveryFixture(mode: "silent")
        defer { fixture.stop() }
        let discovery = TVDiscovery(destinationHost: "127.0.0.1", destinationPort: fixture.udpPort,
                                    httpPort: fixture.httpPort, searchDuration: 2.5, requestTimeout: 1.25)
        let task = Task { try await discovery.discover() }
        try await Task.sleep(nanoseconds: 50_000_000)
        let start = ProcessInfo.processInfo.systemUptime
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected CancellationError") }
        catch is CancellationError {} catch { XCTFail("Wrong error: \(error)") }
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 0.3)
        XCTAssertTrue(try fixture.requests().isEmpty)
    }

    func testCancellationDuringHTTPBodyIsResponsive() async throws {
        let fixture = try DiscoveryFixture(mode: "slowBody")
        defer { fixture.stop() }
        let discovery = TVDiscovery(destinationHost: "127.0.0.1", destinationPort: fixture.udpPort,
                                    httpPort: fixture.httpPort, searchDuration: 0.05, requestTimeout: 1.25)
        let task = Task { try await discovery.discover() }
        let deadline = ProcessInfo.processInfo.systemUptime + 1
        while try fixture.requests().isEmpty, ProcessInfo.processInfo.systemUptime < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(try fixture.requests().count, 1)
        try await Task.sleep(nanoseconds: 50_000_000)
        let start = ProcessInfo.processInfo.systemUptime
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected CancellationError") }
        catch is CancellationError {} catch { XCTFail("Wrong error: \(error)") }
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 0.3)
    }

    func testUnresponsiveHTTPIsBoundedIncludingStreamingBody() async throws {
        for mode in ["slowHeaders", "slowBody"] {
            let fixture = try DiscoveryFixture(mode: mode)
            defer { fixture.stop() }
            let discovery = TVDiscovery(destinationHost: "127.0.0.1", destinationPort: fixture.udpPort,
                                        httpPort: fixture.httpPort, searchDuration: 0.05, requestTimeout: 0.2)
            let start = ProcessInfo.processInfo.systemUptime
            let results = try await discovery.discover()
            XCTAssertTrue(results.isEmpty)
            XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 0.8, mode)
        }
    }

    func testHTTPRedirectIsNeverFollowed() async throws {
        let fixture = try DiscoveryFixture(mode: "redirect")
        defer { fixture.stop() }
        let discovery = TVDiscovery(destinationHost: "127.0.0.1", destinationPort: fixture.udpPort,
                                    httpPort: fixture.httpPort, searchDuration: 0.1, requestTimeout: 0.5)
        let results = try await discovery.discover()
        XCTAssertTrue(results.isEmpty)
        XCTAssertEqual(try fixture.requests().count, 1, "Redirect destination must not receive a request")
    }

    func testLoopbackDiscoverySendsSearchValidatesHTTPAndDeduplicates() async throws {
        let fixture = try DiscoveryFixture()
        defer { fixture.stop() }
        let discovery = TVDiscovery(destinationHost: "127.0.0.1", destinationPort: fixture.udpPort,
                                    httpPort: fixture.httpPort, searchDuration: 0.15, requestTimeout: 0.5)
        let result = try await discovery.discover()
        XCTAssertEqual(result, [DiscoveredTV(host: "127.0.0.1", name: "Loopback TV", model: "QN-Test")])
        let requests = try fixture.requests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?["path"] as? String, "/api/v2/")
        XCTAssertEqual(requests.first?["authorization"] as? String, "")
        XCTAssertEqual(requests.first?["cookie"] as? String, "")
    }

    func testSamsungMetadataUsesSenderNotAdvertisedAddresses() throws {
        let data = Data(#"{"device":{"type":"Samsung SmartTV","name":"Living Room","modelName":"QN55","wifiMac":"AA:BB:CC:DD:EE:10","ip":"8.8.8.8"},"uri":"http://evil/"}"#.utf8)
        XCTAssertEqual(TVDiscovery.parseDevice(data, host: "127.0.0.1"),
                       DiscoveredTV(host: "127.0.0.1", name: "Living Room", model: "QN55", macAddress: "AA:BB:CC:DD:EE:10"))
    }
}

private final class ChallengeSender: NSObject, URLAuthenticationChallengeSender {
    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {}
    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {}
    func cancel(_ challenge: URLAuthenticationChallenge) {}
}

/// Isolated ephemeral loopback UDP + HTTP services; never contacts the LAN.
private final class DiscoveryFixture {
    let process = Process()
    let input = Pipe()
    let output = Pipe()
    let directory: URL
    let udpPort: UInt16
    let httpPort: UInt16

    init(mode: String = "valid") throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("Discovery-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-u", "-c", Self.script, directory.path, mode]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        var line = Data()
        while true {
            var descriptor = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
            guard poll(&descriptor, 1, 5000) > 0, line.count < 128 else {
                process.terminate()
                throw NSError(domain: "DiscoveryFixture", code: 2)
            }
            let byte = output.fileHandleForReading.readData(ofLength: 1)
            guard !byte.isEmpty else { throw NSError(domain: "DiscoveryFixture", code: 1) }
            if byte == Data([10]) { break }
            line.append(byte)
        }
        let ports = try JSONSerialization.jsonObject(with: line) as! [Int]
        udpPort = UInt16(ports[0])
        httpPort = UInt16(ports[1])
    }

    func requests() throws -> [[String: Any]] {
        let data = try Data(contentsOf: directory.appendingPathComponent("requests.json"))
        return try JSONSerialization.jsonObject(with: data) as! [[String: Any]]
    }

    func stop() {
        if process.isRunning {
            try? input.fileHandleForWriting.close()
            // waitUntilExit can miss a run-loop wake on a cooperative Swift worker.
            // Foundation reaps Process children; poll its state with a hard fixture bound.
            let deadline = ProcessInfo.processInfo.systemUptime + 2
            while process.isRunning, ProcessInfo.processInfo.systemUptime < deadline {
                Thread.sleep(forTimeInterval: 0.005)
            }
            if process.isRunning { process.terminate() }
        }
        try? FileManager.default.removeItem(at: directory)
    }
    deinit { stop() }

    private static let script = #"""
import sys, socket, threading, json, http.server, pathlib, time
root, mode = pathlib.Path(sys.argv[1]), sys.argv[2]
requests = []
(root / 'requests.json').write_text('[]')
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        requests.append({'path':self.path, 'authorization':self.headers.get('Authorization',''), 'cookie':self.headers.get('Cookie','')})
        (root / 'requests.new').write_text(json.dumps(requests))
        (root / 'requests.new').replace(root / 'requests.json')
        if mode == 'redirect' and self.path == '/api/v2/':
            self.send_response(302)
            self.send_header('Location','http://127.0.0.1:%d/redirected' % self.server.server_port)
            self.send_header('Content-Length','0')
            self.end_headers()
            return
        if mode == 'slowHeaders': time.sleep(2)
        body = json.dumps({'device':{'type':'Other TV' if mode == 'other' else 'Samsung SmartTV','name':'Loopback TV','modelName':'QN-Test'}}).encode()
        if mode == 'malformed': body = b'bad JSON'
        if mode in ('oversized','streamedOversized'): body += b' ' * 65537
        self.send_response(503 if mode == 'status' else 200)
        if mode != 'streamedOversized': self.send_header('Content-Length',str(len(body)))
        self.end_headers()
        if mode == 'slowBody':
            self.wfile.write(body[:1])
            self.wfile.flush()
            time.sleep(2)
            body = body[1:]
        self.wfile.write(body)
    def log_message(self,*args): pass
http = http.server.ThreadingHTTPServer(('127.0.0.1',0), Handler)
http.daemon_threads = True
threading.Thread(target=http.serve_forever,daemon=True).start()
udp = socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
udp.bind(('127.0.0.1',0))
def respond():
    while True:
        packet, sender = udp.recvfrom(9000)
        if mode == 'silent': continue
        if not (packet.startswith(b'M-SEARCH * HTTP/1.1\r\n') and b'MAN: "ssdp:discover"\r\n' in packet and packet.endswith(b'\r\n\r\n')): continue
        response = b'HTTP/1.1 200 OK\r\nST: upnp:rootdevice\r\nEXT:\r\nBOOTID.UPNP.ORG: 1\r\nSERVER: Samsung\r\nLOCATION: http://127.0.0.2:1/never-follow\r\n\r\n'
        udp.sendto(response,sender)
        udp.sendto(response,sender)
threading.Thread(target=respond,daemon=True).start()
print(json.dumps([udp.getsockname()[1],http.server_port]),flush=True)
sys.stdin.read()
"""#
}
