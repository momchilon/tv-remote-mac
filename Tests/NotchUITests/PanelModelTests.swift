import XCTest
@testable import NotchUI

@MainActor
final class PanelModelTests: XCTestCase {
    func testRemoteCannotSendAnythingUntilAuthenticated() {
        let model = PanelModel()
        var sent: [PanelCommand] = []
        model.onCommand = { sent.append($0) }
        model.send(.up)
        XCTAssertTrue(sent.isEmpty)
        model.connection = .ready
        model.send(.up)
        XCTAssertEqual(sent, [.up])
    }

    func testPowerRequiresExplicitSecondConfirmation() {
        let model = PanelModel()
        model.connection = .ready
        var sent: [PanelCommand] = []
        model.onCommand = { sent.append($0) }
        model.requestPower()
        XCTAssertTrue(model.confirmingPower)
        XCTAssertTrue(sent.isEmpty)
        model.confirmPowerOff()
        XCTAssertEqual(sent, [.power])
        XCTAssertFalse(model.confirmingPower)
    }

    func testConnectionLossCancelsPowerConfirmation() {
        let model = PanelModel()
        model.connection = .ready
        model.requestPower()
        model.connection = .disconnected
        var sent: [PanelCommand] = []
        model.onCommand = { sent.append($0) }
        model.confirmPowerOff()
        XCTAssertTrue(sent.isEmpty)
        XCTAssertFalse(model.confirmingPower)
    }

    func testEmptyAddressDoesNotConnectAndWhitespaceIsTrimmed() {
        let model = PanelModel()
        var hosts: [String] = []
        model.onConnect = { hosts.append($0) }
        model.host = "   "
        model.connect()
        XCTAssertTrue(hosts.isEmpty)
        model.host = " 192.168.1.100 \n"
        model.connect()
        XCTAssertEqual(hosts, ["192.168.1.100"])
        XCTAssertEqual(model.connection, .connecting)
    }

    func testCloseClearsTransientSettingsAndPowerState() {
        let model = PanelModel()
        model.showSettings()
        XCTAssertTrue(model.expanded)
        XCTAssertTrue(model.settings)
        model.close()
        XCTAssertFalse(model.expanded)
        XCTAssertFalse(model.settings)
        XCTAssertFalse(model.confirmingPower)
    }

    func testWakeNoticeDoesNotHideSubsequentConnectionFailures() {
        for message in ["TV denied the connection.", "TV certificate changed.", "TV is offline."] {
            let model = PanelModel()
            model.notice = "Wake request sent. Waiting for TV…"
            model.connection = .failed(message)
            XCTAssertEqual(model.statusDetail, message)
        }
    }

    func testConnectionFailureTakesPrecedenceOverLaterWakeNotice() {
        let model = PanelModel()
        model.connection = .failed("TV denied the connection.")
        model.notice = "Wake request sent. Waiting for TV…"
        XCTAssertEqual(model.statusDetail, "TV denied the connection.")
    }

    func testStatusDetailPreservesNoticesAndNormalConnectionGuidance() {
        let model = PanelModel()
        XCTAssertEqual(model.statusDetail, "Turn on your TV, then reconnect.")
        model.connection = .connecting
        XCTAssertEqual(model.statusDetail, "Connecting over your local network.")
        model.connection = .approval
        XCTAssertEqual(model.statusDetail, "Choose Allow on the TV’s connection prompt.")
        model.notice = "Wake request sent. Waiting for TV…"
        XCTAssertEqual(model.statusDetail, model.notice)
    }

    func testOfflinePowerOffersWakeWithoutSendingAToggle() {
        let model = PanelModel()
        var wake = 0
        var sent: [PanelCommand] = []
        model.onWake = { wake += 1 }
        model.onCommand = { sent.append($0) }
        model.canWake = true
        model.requestPower()
        XCTAssertEqual(wake, 1)
        XCTAssertTrue(sent.isEmpty)
    }
}
