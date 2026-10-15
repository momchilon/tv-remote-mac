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

    func testOnlyExplicitConsumerRemoteKeysAreExposedAndEncoded() throws {
        let expected = """
        KEY_UP KEY_DOWN KEY_LEFT KEY_RIGHT KEY_ENTER KEY_RETURN KEY_HOME
        KEY_VOLUP KEY_VOLDOWN KEY_MUTE KEY_SOURCE KEY_POWER
        KEY_EXIT KEY_MENU KEY_TOOLS KEY_INFO KEY_GUIDE KEY_CH_LIST KEY_PRECH
        KEY_CHUP KEY_CHDOWN KEY_FAVCH KEY_TV KEY_TV_MODE KEY_DTV KEY_ANTENA KEY_DTV_SIGNAL
        KEY_0 KEY_1 KEY_2 KEY_3 KEY_4 KEY_5 KEY_6 KEY_7 KEY_8 KEY_9 KEY_PLUS100
        KEY_RED KEY_GREEN KEY_YELLOW KEY_BLUE
        KEY_PLAY KEY_PAUSE KEY_STOP KEY_REWIND KEY_FF KEY_REC KEY_REPEAT KEY_INSTANT_REPLAY KEY_QUICK_REPLAY
        KEY_CONTENTS KEY_APP_LIST KEY_MORE KEY_HELP KEY_AMBIENT KEY_MULTI_VIEW
        KEY_ANYNET KEY_DEVICE_CONNECT KEY_W_LINK KEY_DISC_MENU KEY_DVR KEY_DVR_MENU KEY_TOPMENU
        KEY_HDMI KEY_HDMI1 KEY_HDMI2 KEY_HDMI3 KEY_HDMI4 KEY_AV1 KEY_AV2 KEY_AV3
        KEY_COMPONENT1 KEY_COMPONENT2 KEY_SVIDEO1 KEY_SVIDEO2 KEY_SVIDEO3 KEY_PCMODE KEY_DVI
        KEY_PMODE KEY_PICTURE_SIZE KEY_ASPECT KEY_16_9 KEY_4_3 KEY_ZOOM1 KEY_ZOOM2
        KEY_ZOOM_IN KEY_ZOOM_OUT KEY_ZOOM_MOVE KEY_PANORAMA KEY_DYNAMIC KEY_STANDARD KEY_MOVIE1
        KEY_STILL_PICTURE KEY_GAME KEY_ESAVING
        KEY_SEFFECT KEY_SRS KEY_MTS KEY_AD KEY_CONVERT_AUDIO_MAINSUB
        KEY_CAPTION KEY_SUB_TITLE KEY_TTX_MIX KEY_TTX_SUBFACE
        KEY_PIP_ONOFF KEY_PIP_CHUP KEY_PIP_CHDOWN KEY_PIP_SWAP KEY_PIP_SIZE KEY_PIP_SCAN
        KEY_SLEEP KEY_CLOCK_DISPLAY KEY_SETUP_CLOCK_TIMER
        """.split(whereSeparator: \.isWhitespace).map(String.init)
        XCTAssertEqual(Set(RemoteKey.allCases.map(\.rawValue)), Set(expected))
        XCTAssertEqual(RemoteKey.allCases.count, expected.count)
        for value in expected {
            let key = try XCTUnwrap(RemoteKey(rawValue: value), value)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(SamsungProtocol.keyMessage(key).utf8)) as? [String: Any])
            XCTAssertEqual(object["method"] as? String, "ms.remote.control")
            XCTAssertEqual(object["params"] as? [String: String], ["Cmd": "Click", "DataOfCmd": value, "Option": "false", "TypeOfRemote": "SendRemoteKey"])
        }
        for forbidden in ["KEY_FACTORY", "KEY_AUTO_ARC_RESET", "KEY_3SPEED", "KEY_AUTO_PROGRAM", "KEY_AUTO_ARC_C_FORCE_AGING", "KEY_EXT1", "KEY_SERVICE", "KEY_POWEROFF", "KEY_POWERON", "KEY_UNKNOWN"] {
            XCTAssertNil(RemoteKey(rawValue: forbidden), forbidden)
        }
    }
}
