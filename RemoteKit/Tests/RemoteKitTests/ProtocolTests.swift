import XCTest
@testable import RemoteKit

final class ProtocolTests: XCTestCase {
    func testHostAcceptsOnlyLiteralLocalIPv4AndTrimsOuterWhitespace() throws {
        for host in ["192.168.1.100", "10.1.2.3", "172.16.0.1", "172.31.255.254", "169.254.2.3", "127.0.0.1"] {
            XCTAssertEqual(try LocalHost(" \n" + host + "\t").value, host)
        }
        for host in ["8.8.8.8", "172.15.0.1", "172.32.0.1", "0.0.0.0", "255.255.255.255", "224.0.0.1", "localhost", "tv.local", "::1", "https://192.168.1.2", "192.168.1.2/path", "192.168.1.2:8002", "192.168.1.2?x=y", "192.168.01.2", "192.168.1.256", "192.168.1", "192.168.1.2\n/", ""] {
            XCTAssertThrowsError(try LocalHost(host), host)
        }
    }

    func testSecureConnectionURLPercentEncodesStandardBase64AndOptionalToken() throws {
        let host = try LocalHost("192.168.1.100")
        let name = "Remote 🏡 / +"
        let url = SamsungProtocol.connectionURL(host: host, clientName: name, token: "a+/=& b")
        XCTAssertEqual(url.scheme, "wss")
        XCTAssertEqual(url.host, host.value)
        XCTAssertEqual(url.port, 8002)
        XCTAssertEqual(url.path, "/api/v2/channels/samsung.remote.control")
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(query.first(where: { $0.name == "name" })?.value, Data(name.utf8).base64EncodedString())
        XCTAssertEqual(query.first(where: { $0.name == "token" })?.value, "a+/=& b")
        XCTAssertTrue(url.absoluteString.contains("%2B"))
        XCTAssertFalse(SamsungProtocol.connectionURL(host: host, clientName: name, token: nil).absoluteString.contains("token="))
    }

    func testChannelCodecGatesAuthenticationAndExtractsOnlyValidTokens() throws {
        XCTAssertEqual(try SamsungProtocol.event(from: #"{"event":"ms.channel.connect","data":{"token":"abc"}}"#), .connected(token: "abc"))
        XCTAssertEqual(try SamsungProtocol.event(from: #"{"event":"ms.channel.connect","data":{"token":123456789}}"#), .connected(token: "123456789"))
        XCTAssertEqual(try SamsungProtocol.event(from: #"{"event":"ms.channel.connect","data":{}}"#), .connected(token: nil))
        XCTAssertEqual(try SamsungProtocol.event(from: #"{"event":"ms.channel.connect","data":{"token":true}}"#), .connected(token: nil))
        XCTAssertEqual(try SamsungProtocol.event(from: #"{"event":"ms.channel.clientConnect"}"#), .ignored)
        for event in ["ms.channel.unauthorized", "ms.channel.timeOut", "ms.error", "ms.channel.error"] {
            XCTAssertThrowsError(try SamsungProtocol.event(from: "{\"event\":\"\(event)\",\"data\":\"secret payload\"}")) { error in
                XCTAssertFalse(error.localizedDescription.contains("secret payload"))
            }
        }
        XCTAssertThrowsError(try SamsungProtocol.event(from: "not-json"))
        XCTAssertThrowsError(try SamsungProtocol.event(from: "[]"))
        let object = try JSONSerialization.jsonObject(with: Data(SamsungProtocol.keyMessage(.enter).utf8)) as! [String: Any]
        XCTAssertEqual(object["method"] as? String, "ms.remote.control")
        XCTAssertEqual(object["params"] as? [String: String], ["Cmd":"Click", "DataOfCmd":"KEY_ENTER", "Option":"false", "TypeOfRemote":"SendRemoteKey"])
    }

    func testOnlyExplicitSafeKeysAreExposed() {
        let expected = ["KEY_UP", "KEY_DOWN", "KEY_LEFT", "KEY_RIGHT", "KEY_ENTER", "KEY_RETURN", "KEY_HOME", "KEY_VOLUP", "KEY_VOLDOWN", "KEY_MUTE", "KEY_SOURCE", "KEY_POWER"]
        XCTAssertEqual(RemoteKey.allCases.map(\.rawValue), expected)
        XCTAssertNil(RemoteKey(rawValue: "KEY_FACTORY"))
    }
}
