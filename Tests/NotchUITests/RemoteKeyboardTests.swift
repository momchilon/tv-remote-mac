import XCTest
@testable import NotchUI

@MainActor
final class RemoteKeyboardTests: XCTestCase {
    func testNumberRowKeypadAndChannelShortcutsSendTheirExactCommands() {
        let model = PanelModel()
        model.connection = .ready
        var sent: [PanelCommand] = []
        model.onCommand = { sent.append($0) }
        let expected: [(UInt16, PanelCommand)] = [
            (18, .digit1), (19, .digit2), (20, .digit3), (21, .digit4), (23, .digit5),
            (22, .digit6), (26, .digit7), (28, .digit8), (25, .digit9), (29, .digit0),
            (83, .digit1), (84, .digit2), (85, .digit3), (86, .digit4), (87, .digit5),
            (88, .digit6), (89, .digit7), (91, .digit8), (92, .digit9), (82, .digit0),
            (116, .channelUp), (121, .channelDown), (126, .up), (125, .down),
            (123, .left), (124, .right), (36, .enter), (76, .enter), (51, .back),
            (24, .volumeUp), (27, .volumeDown), (46, .mute)
        ]
        for (code, _) in expected { XCTAssertTrue(model.handleKey(code, editingText: false)) }
        XCTAssertEqual(sent, expected.map(\.1))
        XCTAssertFalse(model.handleKey(0, editingText: false))
        XCTAssertFalse(model.handleKey(53, editingText: false), "Escape is handled locally, never sent to TV")
    }

    func testSearchSettingsConfirmationAndOfflineStatesCannotSendKeyboardCommands() {
        let model = PanelModel()
        var sent: [PanelCommand] = []
        model.onCommand = { sent.append($0) }
        XCTAssertFalse(model.handleKey(18, editingText: false))
        model.connection = .ready
        for code: UInt16 in [18, 36, 46, 51, 126, 116] {
            XCTAssertFalse(model.handleKey(code, editingText: true))
        }
        model.settings = true
        XCTAssertFalse(model.handleKey(18, editingText: false))
        model.settings = false
        model.requestPower()
        XCTAssertFalse(model.handleKey(18, editingText: false))
        XCTAssertTrue(sent.isEmpty)
    }
}
