import XCTest
@testable import NotchUI

@MainActor
final class PanelModelTests: XCTestCase {
    func testDiscoveryListsTVsWithoutConnectingAndSelectionOnlyFillsAddress() async {
        let model = PanelModel()
        let tv = PanelTV(host: "192.168.1.20", name: "Living room", model: "Samsung QLED")
        var connections = 0
        model.onConnect = { _ in connections += 1 }
        model.onDiscover = { [tv] }
        model.showSettings()
        model.findTVs()
        XCTAssertTrue(model.discovering)
        for _ in 0..<100 where model.discovering { await Task.yield() }
        XCTAssertFalse(model.discovering)
        XCTAssertEqual(model.discoveredTVs, [tv])
        model.selectTV(tv)
        XCTAssertEqual(model.host, tv.host)
        XCTAssertTrue(model.settings)
        XCTAssertEqual(connections, 0)
        XCTAssertEqual(model.connection, .disconnected)
    }

    func testClosingCancelsDiscoveryAndIgnoresLateResults() async {
        let model = PanelModel()
        var finish: CheckedContinuation<[PanelTV], Never>?
        model.onDiscover = { await withCheckedContinuation { finish = $0 } }
        model.showSettings()
        model.findTVs()
        while finish == nil { await Task.yield() }
        model.close()
        XCTAssertFalse(model.discovering)
        finish?.resume(returning: [PanelTV(host: "192.168.1.21", name: "Late TV", model: "TV")])
        for _ in 0..<20 { await Task.yield() }
        XCTAssertTrue(model.discoveredTVs.isEmpty)
        XCTAssertFalse(model.expanded)
    }

    func testSwitchingSavedRemoteConnectsOnlyChosenHost() {
        let model = PanelModel()
        let remote = SavedRemote(host: "192.168.1.22", name: "Bedroom")
        var hosts: [String] = []
        model.onConnect = { hosts.append($0) }
        model.selectRemote(remote)
        XCTAssertEqual(model.host, remote.host)
        XCTAssertEqual(model.remoteName, "Bedroom")
        XCTAssertEqual(hosts, [remote.host])
        XCTAssertEqual(model.connection, .connecting)
    }

    func testAddingRemoteLeavesSavedRemotesAndConnectionUntouched() {
        let model = PanelModel()
        model.savedRemotes = [SavedRemote(host: "192.168.1.22", name: "Bedroom")]
        model.host = "192.168.1.22"
        model.remoteName = "Bedroom"
        model.connection = .ready
        model.addRemote()
        XCTAssertTrue(model.settings)
        XCTAssertEqual(model.host, "")
        XCTAssertEqual(model.remoteName, "")
        XCTAssertEqual(model.savedRemotes.count, 1)
        XCTAssertEqual(model.connection, .ready)
    }

    func testEditingThenLeavingSettingsRestoresActiveRemoteWithoutConnecting() {
        let model = PanelModel()
        let active = SavedRemote(host: "192.168.1.20", name: "Living room")
        let other = SavedRemote(host: "192.168.1.21", name: "Bedroom")
        model.savedRemotes = [active, other]
        model.selectedRemoteHost = active.host
        var connections = 0
        model.onConnect = { _ in connections += 1 }
        model.editRemote(other)
        XCTAssertEqual(model.host, other.host)
        XCTAssertEqual(model.remoteName, other.name)
        XCTAssertTrue(model.settings)
        XCTAssertEqual(model.activeRemoteName, active.name)
        model.leaveSettings()
        XCTAssertFalse(model.settings)
        XCTAssertEqual(model.host, active.host)
        XCTAssertEqual(model.remoteName, active.name)
        XCTAssertEqual(connections, 0)
    }

    func testInvalidAddressCannotConnectOrForgetAnotherTV() {
        let model = PanelModel()
        var connections = 0
        var forgets = 0
        model.onConnect = { _ in connections += 1 }
        model.onForget = { forgets += 1 }
        model.showSettings()
        for host in ["hello", "192.168.1.300", "http://192.168.1.20/", "127.0.0.1"] {
            model.host = host
            model.connect()
            model.repairTV()
            XCTAssertTrue(model.settings)
        }
        XCTAssertEqual(connections, 0)
        XCTAssertEqual(forgets, 0)
        XCTAssertEqual(model.connection, .disconnected)
    }

    func testClosingUnsavedSetupWithoutSelectedRemoteDiscardsDraftBeforeReconnect() {
        let model = PanelModel()
        var hosts: [String] = []
        model.onConnect = { hosts.append($0) }
        model.addRemote()
        model.host = "192.168.1.21"
        model.remoteName = "Unsaved TV"

        model.close()

        XCTAssertFalse(model.settings)
        XCTAssertFalse(model.expanded)
        XCTAssertEqual(model.host, "")
        XCTAssertEqual(model.remoteName, "")
        XCTAssertTrue(model.savedRemotes.isEmpty)
        XCTAssertEqual(model.selectedRemoteHost, "")
        XCTAssertTrue(hosts.isEmpty)
        model.connect()
        XCTAssertTrue(hosts.isEmpty)
        XCTAssertEqual(model.connection, .disconnected)
    }

    func testClosingDraftAfterLastSavedRemoteIsRemovedDiscardsDraftBeforeReconnect() {
        let model = PanelModel()
        let active = SavedRemote(host: "192.168.1.20", name: "Living room")
        model.savedRemotes = [active]
        model.selectedRemoteHost = active.host
        model.host = active.host
        model.remoteName = active.name
        var hosts: [String] = []
        model.onConnect = { hosts.append($0) }
        model.addRemote()
        model.host = "192.168.1.21"
        model.remoteName = "Unsaved TV"
        model.savedRemotes = []
        model.selectedRemoteHost = ""

        model.close()

        XCTAssertFalse(model.settings)
        XCTAssertFalse(model.expanded)
        XCTAssertEqual(model.host, "")
        XCTAssertEqual(model.remoteName, "")
        XCTAssertTrue(model.savedRemotes.isEmpty)
        XCTAssertEqual(model.selectedRemoteHost, "")
        XCTAssertTrue(hosts.isEmpty)
        model.connect()
        XCTAssertTrue(hosts.isEmpty)
        XCTAssertEqual(model.connection, .disconnected)
    }

    func testClosingAnUnsavedDraftRestoresActiveRemoteForReconnect() {
        let model = PanelModel()
        let active = SavedRemote(host: "192.168.1.20", name: "Living room")
        model.savedRemotes = [active]
        model.selectedRemoteHost = active.host
        model.host = active.host
        model.addRemote()
        model.host = "192.168.1.21"
        model.close()
        XCTAssertEqual(model.host, active.host)
        XCTAssertEqual(model.remoteName, active.name)
    }

    func testStoppingSearchAllowsRetryWithoutOldResultsOverwritingIt() async {
        let model = PanelModel()
        var finishOld: CheckedContinuation<[PanelTV], Never>?
        model.onDiscover = { await withCheckedContinuation { finishOld = $0 } }
        model.findTVs()
        while finishOld == nil { await Task.yield() }
        model.cancelDiscovery()
        XCTAssertFalse(model.discoveryNotice.contains("Searching"))
        let current = PanelTV(host: "192.168.1.25", name: "New", model: "TV")
        model.onDiscover = { [current] }
        model.findTVs()
        for _ in 0..<100 where model.discovering { await Task.yield() }
        finishOld?.resume(returning: [PanelTV(host: "192.168.1.26", name: "Old", model: "TV")])
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(model.discoveredTVs, [current])
    }

    func testSettingsHaveRoomForDiscoveryAndSavedRemotes() {
        let model = PanelModel()
        XCTAssertEqual(model.panelHeight, 250)
        model.showSettings()
        XCTAssertEqual(model.panelHeight, 480)
        model.close()
        XCTAssertEqual(model.panelHeight, 250)
    }

    func testEveryMappedConsumerCommandCanReachAuthenticatedTV() throws {
        let model = PanelModel()
        var sent: [PanelCommand] = []
        model.onCommand = { sent.append($0) }
        XCTAssertEqual(PanelCommand.allCases.count, 114)
        for raw in ["KEY_0", "KEY_9", "KEY_CHUP", "KEY_CHDOWN", "KEY_RED", "KEY_GREEN", "KEY_YELLOW", "KEY_BLUE", "KEY_PLAY", "KEY_PAUSE", "KEY_GUIDE", "KEY_HDMI4", "KEY_MULTI_VIEW", "KEY_CAPTION"] {
            XCTAssertNotNil(PanelCommand(rawValue: raw), raw)
        }
        for state: PanelConnection in [.disconnected, .connecting, .approval, .failed("Offline")] {
            model.connection = state
            PanelCommand.allCases.forEach(model.send)
            XCTAssertTrue(sent.isEmpty)
        }
        model.connection = .ready
        PanelCommand.allCases.forEach(model.send)
        XCTAssertEqual(sent, PanelCommand.allCases.filter { $0 != .power })
        XCTAssertFalse(model.confirmingPower)
    }

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
